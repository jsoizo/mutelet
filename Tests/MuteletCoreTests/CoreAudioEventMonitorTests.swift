import CoreAudio
import XCTest
@testable import MuteletCore

final class CoreAudioEventMonitorTests: XCTestCase {
    func testSystemListenerStartupRetriesOnlyMissingAddressAfterPartialFailure() throws {
        let propertyListener = RecordingPropertyListener()
        let monitor = CoreAudioEventMonitor(propertyListener: propertyListener)
        propertyListener.failAdding(selector: kAudioHardwarePropertyDefaultInputDevice)

        XCTAssertThrowsError(try monitor.startSystemListeners())
        propertyListener.allowAdding(selector: kAudioHardwarePropertyDefaultInputDevice)
        XCTAssertNoThrow(try monitor.startSystemListeners())
        XCTAssertNoThrow(try monitor.startSystemListeners())

        XCTAssertEqual(
            propertyListener.events,
            [
                .init(kind: .add, selector: kAudioHardwarePropertyDevices),
                .init(kind: .add, selector: kAudioHardwarePropertyDefaultInputDevice),
                .init(kind: .add, selector: kAudioHardwarePropertyDefaultInputDevice),
            ]
        )
    }

    func testSynchronizingSameDevicesKeepsExistingListeners() {
        let propertyListener = RecordingPropertyListener()
        let monitor = CoreAudioEventMonitor(propertyListener: propertyListener)
        let devices = [descriptor(controls: [.mute, .volume])]

        let initial = monitor.synchronizeDeviceListeners(devices: devices)
        let repeated = monitor.synchronizeDeviceListeners(devices: devices)

        XCTAssertEqual(initial, .init(added: 2, removed: 0, failed: 0))
        XCTAssertEqual(repeated, .init(added: 0, removed: 0, failed: 0))
        XCTAssertEqual(propertyListener.events.map(\.kind), [.add, .add])
    }

    func testSynchronizationAddsReplacementBeforeRemovingObsoleteListener() {
        let propertyListener = RecordingPropertyListener()
        let monitor = CoreAudioEventMonitor(propertyListener: propertyListener)
        _ = monitor.synchronizeDeviceListeners(devices: [descriptor(controls: [.mute])])

        let result = monitor.synchronizeDeviceListeners(
            devices: [descriptor(controls: [.volume])]
        )

        XCTAssertEqual(result, .init(added: 1, removed: 1, failed: 0))
        XCTAssertEqual(
            propertyListener.events,
            [
                .init(kind: .add, selector: kAudioDevicePropertyMute),
                .init(kind: .add, selector: kAudioDevicePropertyVolumeScalar),
                .init(kind: .remove, selector: kAudioDevicePropertyMute),
            ]
        )
    }

    func testFailedReplacementRetainsOldListenerAndRetries() {
        let propertyListener = RecordingPropertyListener()
        let monitor = CoreAudioEventMonitor(propertyListener: propertyListener)
        _ = monitor.synchronizeDeviceListeners(devices: [descriptor(controls: [.mute])])
        propertyListener.failAdding(selector: kAudioDevicePropertyVolumeScalar)

        let failed = monitor.synchronizeDeviceListeners(
            devices: [descriptor(controls: [.volume])]
        )

        XCTAssertEqual(failed, .init(added: 0, removed: 0, failed: 1))
        XCTAssertFalse(propertyListener.events.contains { $0.kind == .remove })

        propertyListener.allowAdding(selector: kAudioDevicePropertyVolumeScalar)
        let retried = monitor.synchronizeDeviceListeners(
            devices: [descriptor(controls: [.volume])]
        )

        XCTAssertEqual(retried, .init(added: 1, removed: 1, failed: 0))
        XCTAssertEqual(propertyListener.events.suffix(2).map(\.kind), [.add, .remove])
    }

    func testChangedUIDReplacesListenerEvenWhenObjectAndAddressMatch() {
        let propertyListener = RecordingPropertyListener()
        let monitor = CoreAudioEventMonitor(propertyListener: propertyListener)
        _ = monitor.synchronizeDeviceListeners(
            devices: [descriptor(uid: "old-device", controls: [.mute])]
        )

        let result = monitor.synchronizeDeviceListeners(
            devices: [descriptor(uid: "new-device", controls: [.mute])]
        )

        XCTAssertEqual(result, .init(added: 1, removed: 1, failed: 0))
        XCTAssertEqual(propertyListener.events.map(\.kind), [.add, .add, .remove])
    }

    func testFailedRemovalRemainsRegisteredAndRetries() {
        let propertyListener = RecordingPropertyListener()
        let monitor = CoreAudioEventMonitor(propertyListener: propertyListener)
        _ = monitor.synchronizeDeviceListeners(devices: [descriptor(controls: [.mute])])
        propertyListener.failRemoving(selector: kAudioDevicePropertyMute)

        let failed = monitor.synchronizeDeviceListeners(
            devices: [descriptor(controls: [.volume])]
        )

        XCTAssertEqual(failed, .init(added: 1, removed: 0, failed: 1))

        propertyListener.allowRemoving(selector: kAudioDevicePropertyMute)
        let retried = monitor.synchronizeDeviceListeners(
            devices: [descriptor(controls: [.volume])]
        )

        XCTAssertEqual(retried, .init(added: 0, removed: 1, failed: 0))
        XCTAssertEqual(propertyListener.events.suffix(2).map(\.kind), [.remove, .remove])
    }

    func testTerminalRemovalFailureDiscardsRegistrationWithoutRetry() async {
        let propertyListener = RecordingPropertyListener()
        let monitor = CoreAudioEventMonitor(
            propertyListener: propertyListener,
            deviceListenerRetryDelay: 0.01
        )
        _ = monitor.synchronizeDeviceListeners(devices: [descriptor(controls: [.mute])])
        propertyListener.failRemoving(
            selector: kAudioDevicePropertyMute,
            status: kAudioHardwareBadObjectError
        )

        let result = monitor.synchronizeDeviceListeners(
            devices: [descriptor(controls: [.volume])]
        )
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(result, .init(added: 1, removed: 1, failed: 0))
        XCTAssertEqual(
            propertyListener.events.filter {
                $0.kind == .remove && $0.selector == kAudioDevicePropertyMute
            }.count,
            1
        )
    }

    func testFailedDeviceRegistrationRetriesWithoutExternalSynchronization() async {
        let propertyListener = RecordingPropertyListener()
        let monitor = CoreAudioEventMonitor(
            propertyListener: propertyListener,
            deviceListenerRetryDelay: 0.01
        )
        propertyListener.failAdding(selector: kAudioDevicePropertyMute)

        let failed = monitor.synchronizeDeviceListeners(
            devices: [descriptor(controls: [.mute])]
        )
        propertyListener.allowAdding(selector: kAudioDevicePropertyMute)

        XCTAssertEqual(failed, .init(added: 0, removed: 0, failed: 1))
        await waitUntil {
            propertyListener.events.filter {
                $0.kind == .add && $0.selector == kAudioDevicePropertyMute
            }.count >= 2
        }
        let synchronized = monitor.synchronizeDeviceListeners(
            devices: [descriptor(controls: [.mute])]
        )
        XCTAssertEqual(synchronized, .init(added: 0, removed: 0, failed: 0))
    }

    func testNewDesiredDevicesCancelPendingRetry() async {
        let propertyListener = RecordingPropertyListener()
        let monitor = CoreAudioEventMonitor(
            propertyListener: propertyListener,
            deviceListenerRetryDelay: 0.05
        )
        propertyListener.failAdding(selector: kAudioDevicePropertyMute)
        _ = monitor.synchronizeDeviceListeners(devices: [descriptor(controls: [.mute])])

        _ = monitor.synchronizeDeviceListeners(devices: [descriptor(controls: [.volume])])
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(
            propertyListener.events.filter {
                $0.kind == .add && $0.selector == kAudioDevicePropertyMute
            }.count,
            1
        )
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Condition was not satisfied")
    }

    private func descriptor(
        uid: String = "test-device",
        controls: [AudioControlKind]
    ) -> AudioDeviceDescriptor {
        AudioDeviceDescriptor(
            objectID: 42,
            uid: uid,
            name: "Test Input",
            inputChannelCount: 1,
            isDefaultInput: true,
            capabilities: AudioDeviceCapabilities(
                nativeMuteControls: controls.contains(.mute)
                    ? [AudioControl(kind: .mute, element: kAudioObjectPropertyElementMain)]
                    : [],
                volumeControls: controls.contains(.volume)
                    ? [AudioControl(kind: .volume, element: kAudioObjectPropertyElementMain)]
                    : []
            )
        )
    }
}

private final class RecordingPropertyListener: CoreAudioPropertyListening {
    enum EventKind: Equatable {
        case add
        case remove
    }

    struct Event: Equatable {
        let kind: EventKind
        let selector: AudioObjectPropertySelector
    }

    private let lock = NSLock()
    private var recordedEvents: [Event] = []
    private var failedAddSelectors: Set<AudioObjectPropertySelector> = []
    private var failedRemoveStatuses: [AudioObjectPropertySelector: OSStatus] = [:]

    var events: [Event] {
        lock.withLock { recordedEvents }
    }

    func failAdding(selector: AudioObjectPropertySelector) {
        _ = lock.withLock { failedAddSelectors.insert(selector) }
    }

    func allowAdding(selector: AudioObjectPropertySelector) {
        _ = lock.withLock { failedAddSelectors.remove(selector) }
    }

    func failRemoving(selector: AudioObjectPropertySelector, status: OSStatus = -1) {
        lock.withLock { failedRemoveStatuses[selector] = status }
    }

    func allowRemoving(selector: AudioObjectPropertySelector) {
        _ = lock.withLock { failedRemoveStatuses.removeValue(forKey: selector) }
    }

    func addPropertyListener(
        objectID: AudioObjectID,
        address: inout AudioObjectPropertyAddress,
        queue: DispatchQueue,
        block: @escaping AudioObjectPropertyListenerBlock
    ) -> OSStatus {
        lock.withLock {
            recordedEvents.append(Event(kind: .add, selector: address.mSelector))
            return failedAddSelectors.contains(address.mSelector) ? -1 : noErr
        }
    }

    func removePropertyListener(
        objectID: AudioObjectID,
        address: inout AudioObjectPropertyAddress,
        queue: DispatchQueue,
        block: @escaping AudioObjectPropertyListenerBlock
    ) -> OSStatus {
        lock.withLock {
            recordedEvents.append(Event(kind: .remove, selector: address.mSelector))
            return failedRemoveStatuses[address.mSelector] ?? noErr
        }
    }
}
