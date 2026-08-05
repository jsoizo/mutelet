import CoreAudio
import Foundation

final class CoreAudioEventMonitor: @unchecked Sendable {
    private enum RegistrationKind {
        case system
        case device
    }

    private struct Registration {
        let kind: RegistrationKind
        let objectID: AudioObjectID
        let address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    private let queue = DispatchQueue(label: "app.mutelet.core-audio-events")
    private let lock = NSLock()
    private var registrations: [Registration] = []
    private var continuations: [UUID: AsyncStream<AudioHardwareEvent>.Continuation] = [:]

    deinit {
        let currentRegistrations = lock.withLock { registrations }
        for registration in currentRegistrations {
            var address = registration.address
            AudioObjectRemovePropertyListenerBlock(
                registration.objectID,
                &address,
                queue,
                registration.block
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

    func replaceDeviceListeners(devices: [AudioDeviceDescriptor]) {
        removeRegistrations(kind: .device)

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
                try? addListener(kind: .device, objectID: device.objectID, address: address)
            }
        }
    }

    private func addListener(
        kind: RegistrationKind,
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
        let status = AudioObjectAddPropertyListenerBlock(
            objectID,
            &mutableAddress,
            queue,
            block
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
                    kind: kind,
                    objectID: objectID,
                    address: address,
                    block: block
                )
            )
        }
    }

    private func removeRegistrations(kind: RegistrationKind) {
        let removed = lock.withLock { () -> [Registration] in
            let matching = registrations.filter { $0.kind == kind }
            registrations.removeAll { $0.kind == kind }
            return matching
        }
        for registration in removed {
            var address = registration.address
            AudioObjectRemovePropertyListenerBlock(
                registration.objectID,
                &address,
                queue,
                registration.block
            )
        }
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
