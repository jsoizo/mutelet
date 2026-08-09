import CoreAudio
import Foundation

protocol CoreAudioPropertyListening {
    func addPropertyListener(
        objectID: AudioObjectID,
        address: inout AudioObjectPropertyAddress,
        queue: DispatchQueue,
        block: @escaping AudioObjectPropertyListenerBlock
    ) -> OSStatus

    func removePropertyListener(
        objectID: AudioObjectID,
        address: inout AudioObjectPropertyAddress,
        queue: DispatchQueue,
        block: @escaping AudioObjectPropertyListenerBlock
    ) -> OSStatus
}

struct SystemCoreAudioPropertyListener: CoreAudioPropertyListening {
    func addPropertyListener(
        objectID: AudioObjectID,
        address: inout AudioObjectPropertyAddress,
        queue: DispatchQueue,
        block: @escaping AudioObjectPropertyListenerBlock
    ) -> OSStatus {
        AudioObjectAddPropertyListenerBlock(objectID, &address, queue, block)
    }

    func removePropertyListener(
        objectID: AudioObjectID,
        address: inout AudioObjectPropertyAddress,
        queue: DispatchQueue,
        block: @escaping AudioObjectPropertyListenerBlock
    ) -> OSStatus {
        AudioObjectRemovePropertyListenerBlock(objectID, &address, queue, block)
    }
}

final class CoreAudioEventMonitor: @unchecked Sendable {
    private enum RegistrationKind {
        case system
        case device
    }

    private struct Registration {
        let identifier: UUID
        let kind: RegistrationKind
        let deviceUID: String?
        let objectID: AudioObjectID
        let address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    private struct DeviceRegistrationKey: Hashable {
        let deviceUID: String
        let objectID: AudioObjectID
        let selector: AudioObjectPropertySelector
        let scope: AudioObjectPropertyScope
        let element: AudioObjectPropertyElement
    }

    struct SynchronizationResult: Equatable {
        let added: Int
        let removed: Int
        let failed: Int
    }

    private let queue = DispatchQueue(label: "app.mutelet.core-audio-events")
    private let lock = NSLock()
    private let propertyListener: any CoreAudioPropertyListening
    private var registrations: [Registration] = []
    private var continuations: [UUID: AsyncStream<AudioHardwareEvent>.Continuation] = [:]

    init(propertyListener: any CoreAudioPropertyListening = SystemCoreAudioPropertyListener()) {
        self.propertyListener = propertyListener
    }

    deinit {
        let currentRegistrations = lock.withLock { registrations }
        for registration in currentRegistrations {
            var address = registration.address
            _ = propertyListener.removePropertyListener(
                objectID: registration.objectID,
                address: &address,
                queue: queue,
                block: registration.block
            )
        }
    }

    func stream() -> AsyncStream<AudioHardwareEvent> {
        let identifier = UUID()
        return AsyncStream { continuation in
            lock.withLock {
                continuations[identifier] = continuation
            }
            continuation.onTermination = { [weak self] _ in
                _ = self?.lock.withLock {
                    self?.continuations.removeValue(forKey: identifier)
                }
            }
        }
    }

    func startSystemListeners() throws {
        let shouldStart = lock.withLock {
            !registrations.contains { $0.kind == .system }
        }
        guard shouldStart else { return }

        try addListener(
            kind: .system,
            objectID: CoreAudioPropertyAccess.systemObject,
            address: CoreAudioPropertyAccess.address(
                selector: kAudioHardwarePropertyDevices
            )
        )
        do {
            try addListener(
                kind: .system,
                objectID: CoreAudioPropertyAccess.systemObject,
                address: CoreAudioPropertyAccess.address(
                    selector: kAudioHardwarePropertyDefaultInputDevice
                )
            )
        } catch {
            removeRegistrations(kind: .system)
            throw error
        }
    }

    @discardableResult
    func synchronizeDeviceListeners(
        devices: [AudioDeviceDescriptor]
    ) -> SynchronizationResult {
        var desired: [DeviceRegistrationKey: AudioObjectPropertyAddress] = [:]
        for device in devices {
            let controls = device.capabilities.nativeMuteControls + device.capabilities.volumeControls
            for control in controls {
                let selector: AudioObjectPropertySelector = switch control.kind {
                case .mute: kAudioDevicePropertyMute
                case .volume: kAudioDevicePropertyVolumeScalar
                }
                let address = CoreAudioPropertyAccess.address(
                    selector: selector,
                    scope: kAudioObjectPropertyScopeInput,
                    element: control.element
                )
                desired[
                    DeviceRegistrationKey(
                        deviceUID: device.uid,
                        objectID: device.objectID,
                        selector: address.mSelector,
                        scope: address.mScope,
                        element: address.mElement
                    )
                ] = address
            }
        }

        let current: [DeviceRegistrationKey: Registration] = lock.withLock {
            var current: [DeviceRegistrationKey: Registration] = [:]
            for registration in registrations where registration.kind == .device {
                guard let deviceUID = registration.deviceUID else { continue }
                current[
                    DeviceRegistrationKey(
                        deviceUID: deviceUID,
                        objectID: registration.objectID,
                        selector: registration.address.mSelector,
                        scope: registration.address.mScope,
                        element: registration.address.mElement
                    )
                ] = registration
            }
            return current
        }

        let missingKeys = Set(desired.keys).subtracting(current.keys)
        var added = 0
        var failed = 0
        for key in missingKeys {
            guard let address = desired[key] else { continue }
            do {
                try addListener(
                    kind: .device,
                    deviceUID: key.deviceUID,
                    objectID: key.objectID,
                    address: address
                )
                added += 1
            } catch {
                failed += 1
                CoreAudioDiagnostics.listenerRegistrationFailed(
                    objectID: key.objectID,
                    address: address,
                    error: error
                )
            }
        }

        guard failed == 0 else {
            return SynchronizationResult(added: added, removed: 0, failed: failed)
        }

        let obsoleteKeys = Set(current.keys).subtracting(desired.keys)
        let obsoleteRegistrations = obsoleteKeys.compactMap { current[$0] }
        let removal = remove(registrations: obsoleteRegistrations)
        return SynchronizationResult(
            added: added,
            removed: removal.removed,
            failed: removal.failed
        )
    }

    private func addListener(
        kind: RegistrationKind,
        deviceUID: String? = nil,
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress
    ) throws {
        let block: AudioObjectPropertyListenerBlock = { [weak self] count, addresses in
            guard let self else { return }
            let changedAddresses = UnsafeBufferPointer(start: addresses, count: Int(count))
            for changedAddress in changedAddresses {
                let eventKind: AudioHardwareEventKind
                if objectID == CoreAudioPropertyAccess.systemObject,
                   changedAddress.mSelector == kAudioHardwarePropertyDevices {
                    eventKind = .deviceListChanged
                } else if objectID == CoreAudioPropertyAccess.systemObject,
                          changedAddress.mSelector == kAudioHardwarePropertyDefaultInputDevice {
                    eventKind = .defaultInputChanged
                } else {
                    eventKind = .controlValueChanged
                }
                self.emit(
                    AudioHardwareEvent(
                        kind: eventKind,
                        objectID: objectID,
                        selector: changedAddress.mSelector,
                        element: changedAddress.mElement
                    )
                )
            }
        }

        var mutableAddress = address
        let status = propertyListener.addPropertyListener(
            objectID: objectID,
            address: &mutableAddress,
            queue: queue,
            block: block
        )
        guard status == noErr else {
            throw CoreAudioError.operationFailed(
                operation: "registering Core Audio property listener",
                status: status
            )
        }
        lock.withLock {
            registrations.append(
                Registration(
                    identifier: UUID(),
                    kind: kind,
                    deviceUID: deviceUID,
                    objectID: objectID,
                    address: address,
                    block: block
                )
            )
        }
    }

    private func removeRegistrations(kind: RegistrationKind) {
        let matching = lock.withLock {
            registrations.filter { $0.kind == kind }
        }
        remove(registrations: matching)
    }

    @discardableResult
    private func remove(
        registrations candidates: [Registration]
    ) -> (removed: Int, failed: Int) {
        var removedCount = 0
        var failedCount = 0
        for registration in candidates {
            var address = registration.address
            let status = propertyListener.removePropertyListener(
                objectID: registration.objectID,
                address: &address,
                queue: queue,
                block: registration.block
            )
            if status == noErr {
                lock.withLock {
                    registrations.removeAll { $0.identifier == registration.identifier }
                }
                removedCount += 1
            } else {
                failedCount += 1
                CoreAudioDiagnostics.listenerRemovalFailed(
                    objectID: registration.objectID,
                    address: address,
                    status: status
                )
            }
        }
        return (removedCount, failedCount)
    }

    private func emit(_ event: AudioHardwareEvent) {
        let currentContinuations = lock.withLock {
            Array(continuations.values)
        }
        for continuation in currentContinuations {
            continuation.yield(event)
        }
    }
}
