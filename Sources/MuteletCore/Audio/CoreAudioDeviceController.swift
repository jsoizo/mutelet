import CoreAudio
import Foundation

public actor CoreAudioDeviceController: AudioDeviceControlling {
    private let eventMonitor = CoreAudioEventMonitor()

    public init() {}

    public func inputDevices() async throws -> [AudioDeviceDescriptor] {
        let defaultInputID = try readDefaultInputObjectID()
        let address = CoreAudioPropertyAccess.address(selector: kAudioHardwarePropertyDevices)
        let objectIDs: [AudioObjectID] = try CoreAudioPropertyAccess.array(
            objectID: CoreAudioPropertyAccess.systemObject,
            address: address,
            operation: "reading Core Audio device list"
        )

        var devices: [AudioDeviceDescriptor] = []
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
            let channelCount = try inputChannelCount(objectID: objectID)
            guard channelCount > 0 else {
                continue
            }
            do {
                devices.append(
                    try descriptor(
                        objectID: objectID,
                        channelCount: channelCount,
                        defaultInputID: defaultInputID
                    )
                )
            } catch {
                devices.append(
                    AudioDeviceDescriptor(
                        objectID: objectID,
                        uid: "unresolved-core-audio-object-\(objectID)",
                        name: "Unreadable Input \(objectID)",
                        inputChannelCount: channelCount,
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

        eventMonitor.replaceDeviceListeners(devices: devices)
        return devices
    }

    public func defaultInputDevice() async throws -> AudioDeviceDescriptor? {
        let defaultInputID = try readDefaultInputObjectID()
        guard defaultInputID != kAudioObjectUnknown else { return nil }
        let channelCount = try inputChannelCount(objectID: defaultInputID)
        guard channelCount > 0 else { return nil }
        return try descriptor(
            objectID: defaultInputID,
            channelCount: channelCount,
            defaultInputID: defaultInputID
        )
    }

    public func snapshot(deviceUID: String) async throws -> AudioDeviceSnapshot {
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
        if let receipt, receipt.deviceUID != deviceUID {
            throw CoreAudioError.invalidRestoration(
                expectedUID: deviceUID,
                actualUID: receipt.deviceUID
            )
        }
        let original = try await snapshot(deviceUID: deviceUID)
        guard original.device.capabilities.isSupported else {
            throw CoreAudioError.unsupportedDevice(uid: deviceUID)
        }
        if let receipt {
            let availableControls = Set(
                original.device.capabilities.nativeMuteControls
                    + original.device.capabilities.volumeControls
            )
            guard receipt.originalValues.allSatisfy({
                availableControls.contains($0.control)
            }) else {
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

    public func unmute(
        deviceUID: String,
        restoring receipt: AudioMutationReceipt?
    ) async throws {
        let current = try await snapshot(deviceUID: deviceUID)
        if let receipt {
            guard receipt.deviceUID == deviceUID else {
                throw CoreAudioError.invalidRestoration(
                    expectedUID: deviceUID,
                    actualUID: receipt.deviceUID
                )
            }
            let availableControls = Set(
                current.device.capabilities.nativeMuteControls
                    + current.device.capabilities.volumeControls
            )
            guard receipt.originalValues.allSatisfy({
                availableControls.contains($0.control)
            }) else {
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
        try eventMonitor.startSystemListeners()
        _ = try await inputDevices()
        return eventMonitor.stream()
    }

    private func device(uid: String) async throws -> AudioDeviceDescriptor {
        guard let device = try await inputDevices().first(where: { $0.uid == uid }) else {
            throw CoreAudioError.deviceNotFound(uid: uid)
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
        let uid = try CoreAudioPropertyAccess.string(
            objectID: objectID,
            address: CoreAudioPropertyAccess.address(
                selector: kAudioDevicePropertyDeviceUID
            ),
            operation: "reading input device UID"
        )
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
            capabilities: capabilities(objectID: objectID, channelCount: channelCount)
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
    ) -> AudioDeviceCapabilities {
        let muteControls = writableControls(
            kind: .mute,
            objectID: objectID,
            channelCount: channelCount
        )
        let volumeControls = writableControls(
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
    ) -> [AudioControl] {
        let mainControl = AudioControl(kind: kind, element: kAudioObjectPropertyElementMain)
        let mainAddress = address(for: mainControl)
        if CoreAudioPropertyAccess.hasProperty(objectID: objectID, address: mainAddress),
           CoreAudioPropertyAccess.isSettable(objectID: objectID, address: mainAddress) {
            return [mainControl]
        }

        return (1...channelCount).compactMap { channel in
            let control = AudioControl(kind: kind, element: channel)
            let controlAddress = address(for: control)
            guard CoreAudioPropertyAccess.hasProperty(objectID: objectID, address: controlAddress),
                  CoreAudioPropertyAccess.isSettable(objectID: objectID, address: controlAddress) else {
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
