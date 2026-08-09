import CoreAudio
import XCTest
@testable import MuteletCore

final class CoreAudioEventMonitorTests: XCTestCase {
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
    private var failedRemoveSelectors: Set<AudioObjectPropertySelector> = []

    var events: [Event] {
        lock.withLock { recordedEvents }
    }

    func failAdding(selector: AudioObjectPropertySelector) {
        _ = lock.withLock { failedAddSelectors.insert(selector) }
    }

    func allowAdding(selector: AudioObjectPropertySelector) {
        _ = lock.withLock { failedAddSelectors.remove(selector) }
    }

    func failRemoving(selector: AudioObjectPropertySelector) {
        _ = lock.withLock { failedRemoveSelectors.insert(selector) }
    }

    func allowRemoving(selector: AudioObjectPropertySelector) {
        _ = lock.withLock { failedRemoveSelectors.remove(selector) }
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
            return failedRemoveSelectors.contains(address.mSelector) ? -1 : noErr
        }
    }
}
