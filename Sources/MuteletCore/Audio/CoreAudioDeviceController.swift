import CoreAudio
import Foundation

struct CoreAudioDeviceInventory: Sendable {
    let devices: [AudioDeviceDescriptor]
    let isComplete: Bool
}

public actor CoreAudioDeviceController: AudioDeviceControlling {
    private struct InventoryCache {
        let revision: UInt64
        let devices: [AudioDeviceDescriptor]
    }

    private let eventMonitor: CoreAudioEventMonitor
    private let inventoryProvider: (@Sendable () throws -> CoreAudioDeviceInventory)?
    private var inventoryCache: InventoryCache?

    public init() {
        eventMonitor = CoreAudioEventMonitor()
        inventoryProvider = nil
    }

    init(
        eventMonitor: CoreAudioEventMonitor,
        inventoryProvider: @escaping @Sendable () throws -> CoreAudioDeviceInventory
    ) {
        self.eventMonitor = eventMonitor
        self.inventoryProvider = inventoryProvider
    }

    public func inputDevices() async throws -> [AudioDeviceDescriptor] {
        let measurement = CoreAudioDiagnostics.measure("inputDevices")
        defer { measurement.finish() }

        try eventMonitor.startSystemListeners()
        let revision = eventMonitor.currentInventoryRevision()
        if let inventoryCache, inventoryCache.revision == revision {
            CoreAudioDiagnostics.mark("inputDevices.cacheHit")
            return inventoryCache.devices
        }

        CoreAudioDiagnostics.mark("inputDevices.cacheMiss")
        let inventory = try inventoryProvider?() ?? enumerateInputDevices()
        let devices = inventory.devices
        let synchronization = eventMonitor.synchronizeDeviceListeners(devices: devices)
        if inventory.isComplete,
           synchronization.failed == 0,
           eventMonitor.currentInventoryRevision() == revision {
            inventoryCache = InventoryCache(revision: revision, devices: devices)
        } else {
            inventoryCache = nil
        }
        return devices
    }

    private func enumerateInputDevices() throws -> CoreAudioDeviceInventory {
        let defaultInputID = try readDefaultInputObjectID()
        let address = CoreAudioPropertyAccess.address(selector: kAudioHardwarePropertyDevices)
        let objectIDs: [AudioObjectID] = try CoreAudioPropertyAccess.array(
            objectID: CoreAudioPropertyAccess.systemObject,
            address: address,
            operation: "reading Core Audio device list"
        )

        var devices: [AudioDeviceDescriptor] = []
        var isComplete = true
        for objectID in objectIDs {
            let streamAddress = CoreAudioPropertyAccess.address(
                selector: kAudioDevicePropertyStreamConfiguration,
                scope: kAudioObjectPropertyScopeInput
            )
            guard CoreAudioPropertyAccess.hasProperty(
                objectID: objectID,
                address: streamAddress
            ) else {
                continue
            }
            do {
                let channelCount = try inputChannelCount(objectID: objectID)
                guard channelCount > 0 else { continue }
                devices.append(
                    try descriptor(
                        objectID: objectID,
                        channelCount: channelCount,
                        defaultInputID: defaultInputID
                    )
                )
            } catch {
                isComplete = false
                let uid = (try? readDeviceUID(objectID: objectID))
                    ?? "unresolved-core-audio-object-\(objectID)"
                let name = (try? CoreAudioPropertyAccess.string(
                    objectID: objectID,
                    address: CoreAudioPropertyAccess.address(
                        selector: kAudioObjectPropertyName
                    ),
                    operation: "reading input device name"
                )) ?? "Unreadable Input \(objectID)"
                devices.append(
                    AudioDeviceDescriptor(
                        objectID: objectID,
                        uid: uid,
                        name: name,
                        inputChannelCount: 0,
                        isDefaultInput: objectID == defaultInputID,
                        capabilities: AudioDeviceCapabilities(
                            nativeMuteControls: [],
                            volumeControls: [],
                            coversAllInputChannels: false
                        )
                    )
                )
            }
        }
        devices.sort { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        return CoreAudioDeviceInventory(devices: devices, isComplete: isComplete)
    }

    public func defaultInputDevice() async throws -> AudioDeviceDescriptor? {
        try await inputDevices().first(where: \.isDefaultInput)
    }

    public func snapshot(deviceUID: String) async throws -> AudioDeviceSnapshot {
        let measurement = CoreAudioDiagnostics.measure("snapshot")
        defer { measurement.finish() }

        let device = try await device(uid: deviceUID)
        var values: [AudioControlValue] = []
        for control in device.capabilities.nativeMuteControls + device.capabilities.volumeControls {
            values.append(
                AudioControlValue(
                    control: control,
                    value: try read(control: control, objectID: device.objectID)
                )
            )
        }
        return AudioDeviceSnapshot(device: device, values: values)
    }

    public func mute(
        deviceUID: String,
        preserving receipt: AudioMutationReceipt?
    ) async throws -> AudioMutationReceipt {
        let snapshot = try await snapshot(deviceUID: deviceUID)
        return try await mute(
            deviceUID: deviceUID,
            preserving: receipt,
            expected: snapshot
        )
    }

    public func mute(
        deviceUID: String,
        preserving receipt: AudioMutationReceipt?,
        expected expectedSnapshot: AudioDeviceSnapshot
    ) async throws -> AudioMutationReceipt {
        let measurement = CoreAudioDiagnostics.measure("mute")
        defer { measurement.finish() }

        if let receipt, receipt.deviceUID != deviceUID {
            throw CoreAudioError.invalidRestoration(
                expectedUID: deviceUID,
                actualUID: receipt.deviceUID
            )
        }
        let original = try await snapshot(deviceUID: deviceUID)
        guard Self.snapshot(original, matches: expectedSnapshot) else {
            throw CoreAudioError.staleSnapshot(uid: deviceUID)
        }
        guard original.device.capabilities.isSupported else {
            throw CoreAudioError.unsupportedDevice(uid: deviceUID)
        }
        if let receipt {
            guard receipt.hasSameControls(as: original.values) else {
                throw CoreAudioError.incompleteRestoration(uid: deviceUID)
            }
        }

        do {
            for control in original.device.capabilities.nativeMuteControls {
                try write(value: 1, control: control, objectID: original.device.objectID)
            }
            for control in original.device.capabilities.volumeControls {
                try write(value: 0, control: control, objectID: original.device.objectID)
            }
        } catch {
            try? restoreValues(original.values, on: original.device.objectID)
            throw error
        }

        return receipt ?? AudioMutationReceipt(
            deviceUID: deviceUID,
            originalValues: original.values
        )
    }

    private static func snapshot(
        _ lhs: AudioDeviceSnapshot,
        matches rhs: AudioDeviceSnapshot
    ) -> Bool {
        guard lhs.device.uid == rhs.device.uid,
              lhs.device.capabilities == rhs.device.capabilities else { return false }
        let lhsValues = Dictionary(uniqueKeysWithValues: lhs.values.map { ($0.control, $0.value) })
        let rhsValues = Dictionary(uniqueKeysWithValues: rhs.values.map { ($0.control, $0.value) })
        guard lhsValues.keys == rhsValues.keys else { return false }
        return lhsValues.allSatisfy { control, value in
            guard let other = rhsValues[control] else { return false }
            return abs(value - other) <= 0.0001
        }
    }

    public func unmute(
        deviceUID: String,
        restoring receipt: AudioMutationReceipt?
    ) async throws {
        let measurement = CoreAudioDiagnostics.measure("unmute")
        defer { measurement.finish() }

        let current = try await snapshot(deviceUID: deviceUID)
        if let receipt {
            guard receipt.deviceUID == deviceUID else {
                throw CoreAudioError.invalidRestoration(
                    expectedUID: deviceUID,
                    actualUID: receipt.deviceUID
                )
            }
            guard receipt.hasSameControls(as: current.values) else {
                throw CoreAudioError.incompleteRestoration(uid: deviceUID)
            }
            try restoreValues(receipt.originalValues, on: current.device.objectID)
            return
        }

        guard !current.device.capabilities.nativeMuteControls.isEmpty else {
            throw CoreAudioError.missingRestoration(uid: deviceUID)
        }
        for control in current.device.capabilities.nativeMuteControls {
            try write(value: 0, control: control, objectID: current.device.objectID)
        }
    }

    public func events() async throws -> AsyncStream<AudioHardwareEvent> {
        let stream = eventMonitor.stream()
        _ = try await inputDevices()
        return stream
    }

    private func device(
        uid: String,
        retryingAfterInvalidation: Bool = false
    ) async throws -> AudioDeviceDescriptor {
        guard let device = try await inputDevices().first(where: { $0.uid == uid }) else {
            throw CoreAudioError.deviceNotFound(uid: uid)
        }
        guard !device.uid.hasPrefix("unresolved-core-audio-object-") else {
            return device
        }
        do {
            let resolvedUID = try readDeviceUID(objectID: device.objectID)
            guard resolvedUID == uid else {
                throw CoreAudioError.deviceNotFound(uid: uid)
            }
        } catch {
            inventoryCache = nil
            if !retryingAfterInvalidation {
                return try await self.device(uid: uid, retryingAfterInvalidation: true)
            }
            throw error
        }
        return device
    }

    private func readDefaultInputObjectID() throws -> AudioObjectID {
        let address = CoreAudioPropertyAccess.address(
            selector: kAudioHardwarePropertyDefaultInputDevice
        )
        return try CoreAudioPropertyAccess.scalar(
            objectID: CoreAudioPropertyAccess.systemObject,
            address: address,
            operation: "reading default input device",
            as: AudioObjectID.self
        )
    }

    private func descriptor(
        objectID: AudioObjectID,
        channelCount: UInt32,
        defaultInputID: AudioObjectID
    ) throws -> AudioDeviceDescriptor {
        let uid = try readDeviceUID(objectID: objectID)
        let name = try CoreAudioPropertyAccess.string(
            objectID: objectID,
            address: CoreAudioPropertyAccess.address(
                selector: kAudioObjectPropertyName
            ),
            operation: "reading input device name"
        )
        return AudioDeviceDescriptor(
            objectID: objectID,
            uid: uid,
            name: name,
            inputChannelCount: channelCount,
            isDefaultInput: objectID == defaultInputID,
            capabilities: try capabilities(objectID: objectID, channelCount: channelCount)
        )
    }

    private func readDeviceUID(objectID: AudioObjectID) throws -> String {
        try CoreAudioPropertyAccess.string(
            objectID: objectID,
            address: CoreAudioPropertyAccess.address(
                selector: kAudioDevicePropertyDeviceUID
            ),
            operation: "reading input device UID"
        )
    }

    private func inputChannelCount(objectID: AudioObjectID) throws -> UInt32 {
        let address = CoreAudioPropertyAccess.address(
            selector: kAudioDevicePropertyStreamConfiguration,
            scope: kAudioObjectPropertyScopeInput
        )
        let byteCount = try CoreAudioPropertyAccess.dataSize(
            objectID: objectID,
            address: address,
            operation: "reading input stream configuration size"
        )
        guard byteCount >= MemoryLayout<AudioBufferList>.size else { return 0 }

        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: Int(byteCount),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { storage.deallocate() }
        let bufferList = storage.bindMemory(to: AudioBufferList.self, capacity: 1)
        var mutableAddress = address
        var mutableByteCount = byteCount
        let status = AudioObjectGetPropertyData(
            objectID,
            &mutableAddress,
            0,
            nil,
            &mutableByteCount,
            bufferList
        )
        guard status == noErr else {
            throw CoreAudioError.operationFailed(
                operation: "reading input stream configuration",
                status: status
            )
        }

        return UnsafeMutableAudioBufferListPointer(bufferList).reduce(0) {
            $0 + $1.mNumberChannels
        }
    }

    private func capabilities(
        objectID: AudioObjectID,
        channelCount: UInt32
    ) throws -> AudioDeviceCapabilities {
        let muteControls = try writableControls(
            kind: .mute,
            objectID: objectID,
            channelCount: channelCount
        )
        let volumeControls = try writableControls(
            kind: .volume,
            objectID: objectID,
            channelCount: channelCount
        )
        let controls = muteControls + volumeControls
        let hasMainControl = controls.contains(where: \.isMain)
        let controlledChannels = Set(
            controls.lazy.filter { !$0.isMain }.map(\.element)
        )
        let coversEveryChannel = hasMainControl
            || (1...channelCount).allSatisfy(controlledChannels.contains)
        return AudioDeviceCapabilities(
            nativeMuteControls: muteControls,
            volumeControls: volumeControls,
            coversAllInputChannels: coversEveryChannel
        )
    }

    private func writableControls(
        kind: AudioControlKind,
        objectID: AudioObjectID,
        channelCount: UInt32
    ) throws -> [AudioControl] {
        let mainControl = AudioControl(kind: kind, element: kAudioObjectPropertyElementMain)
        let mainAddress = address(for: mainControl)
        if CoreAudioPropertyAccess.hasProperty(objectID: objectID, address: mainAddress),
           try CoreAudioPropertyAccess.isSettable(objectID: objectID, address: mainAddress) {
            return [mainControl]
        }

        return try (1...channelCount).compactMap { channel in
            let control = AudioControl(kind: kind, element: channel)
            let controlAddress = address(for: control)
            guard CoreAudioPropertyAccess.hasProperty(objectID: objectID, address: controlAddress),
                  try CoreAudioPropertyAccess.isSettable(
                      objectID: objectID,
                      address: controlAddress
                  ) else {
                return nil
            }
            return control
        }
    }

    private func read(control: AudioControl, objectID: AudioObjectID) throws -> Float {
        switch control.kind {
        case .mute:
            let value: UInt32 = try CoreAudioPropertyAccess.scalar(
                objectID: objectID,
                address: address(for: control),
                operation: "reading input mute"
            )
            return Float(value)
        case .volume:
            let value: Float32 = try CoreAudioPropertyAccess.scalar(
                objectID: objectID,
                address: address(for: control),
                operation: "reading input volume"
            )
            return value
        }
    }

    private func write(value: Float, control: AudioControl, objectID: AudioObjectID) throws {
        switch control.kind {
        case .mute:
            try CoreAudioPropertyAccess.setScalar(
                UInt32(value.rounded()),
                objectID: objectID,
                address: address(for: control),
                operation: "writing input mute"
            )
        case .volume:
            try CoreAudioPropertyAccess.setScalar(
                Float32(value),
                objectID: objectID,
                address: address(for: control),
                operation: "writing input volume"
            )
        }
    }

    private func restoreValues(
        _ values: [AudioControlValue],
        on objectID: AudioObjectID
    ) throws {
        for value in values where value.control.kind == .volume {
            try write(value: value.value, control: value.control, objectID: objectID)
        }
        for value in values where value.control.kind == .mute {
            try write(value: value.value, control: value.control, objectID: objectID)
        }
    }

    private func address(for control: AudioControl) -> AudioObjectPropertyAddress {
        let selector: AudioObjectPropertySelector = switch control.kind {
        case .mute: kAudioDevicePropertyMute
        case .volume: kAudioDevicePropertyVolumeScalar
        }
        return CoreAudioPropertyAccess.address(
            selector: selector,
            scope: kAudioObjectPropertyScopeInput,
            element: control.element
        )
    }
}
