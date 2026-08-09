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

        XCTAssertEqual(initial, .init(added: 4, removed: 0, failed: 0))
        XCTAssertEqual(repeated, .init(added: 0, removed: 0, failed: 0))
        XCTAssertEqual(propertyListener.events.map(\.kind), Array(repeating: .add, count: 4))
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
            propertyListener.events.filter {
                $0.selector == kAudioDevicePropertyMute
                    || $0.selector == kAudioDevicePropertyVolumeScalar
            },
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

        XCTAssertEqual(result, .init(added: 3, removed: 3, failed: 0))
        XCTAssertEqual(
            propertyListener.events.filter { $0.selector == kAudioDevicePropertyMute }.map(\.kind),
            [.add, .add, .remove]
        )
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

        XCTAssertEqual(failed, .init(added: 2, removed: 0, failed: 1))
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

    func testSystemAndTopologyEventsAdvanceInventoryRevision() throws {
        let propertyListener = RecordingPropertyListener()
        let monitor = CoreAudioEventMonitor(propertyListener: propertyListener)
        try monitor.startSystemListeners()
        let initialRevision = monitor.currentInventoryRevision()

        propertyListener.emit(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDevices
        )
        XCTAssertEqual(monitor.currentInventoryRevision(), initialRevision + 1)

        propertyListener.emit(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDefaultInputDevice
        )
        XCTAssertEqual(monitor.currentInventoryRevision(), initialRevision + 2)

        _ = monitor.synchronizeDeviceListeners(devices: [descriptor(controls: [.mute])])
        propertyListener.emit(
            objectID: 42,
            selector: kAudioDevicePropertyStreamConfiguration
        )
        XCTAssertEqual(monitor.currentInventoryRevision(), initialRevision + 3)

        propertyListener.emit(objectID: 42, selector: kAudioObjectPropertyControlList)
        XCTAssertEqual(monitor.currentInventoryRevision(), initialRevision + 4)

        propertyListener.emit(objectID: 42, selector: kAudioDevicePropertyMute)
        XCTAssertEqual(monitor.currentInventoryRevision(), initialRevision + 4)
    }

    func testDegradedInventoryIsReenumeratedUntilACompleteResultCanBeCached() async throws {
        let propertyListener = RecordingPropertyListener()
        let monitor = CoreAudioEventMonitor(propertyListener: propertyListener)
        let device = descriptor(controls: [.mute])
        let inventoryProvider = RecordingInventoryProvider(
            inventories: [
                CoreAudioDeviceInventory(devices: [device], isComplete: false),
                CoreAudioDeviceInventory(devices: [device], isComplete: true),
            ]
        )
        let controller = CoreAudioDeviceController(
            eventMonitor: monitor,
            inventoryProvider: { inventoryProvider.next() }
        )

        _ = try await controller.inputDevices()
        _ = try await controller.inputDevices()
        _ = try await controller.inputDevices()

        XCTAssertEqual(inventoryProvider.callCount, 2)
    }

    func testTopologyEventInvalidatesCachedInventory() async throws {
        let propertyListener = RecordingPropertyListener()
        let monitor = CoreAudioEventMonitor(propertyListener: propertyListener)
        let inventoryProvider = RecordingInventoryProvider(
            inventories: [
                CoreAudioDeviceInventory(
                    devices: [descriptor(controls: [.mute])],
                    isComplete: true
                ),
            ]
        )
        let controller = CoreAudioDeviceController(
            eventMonitor: monitor,
            inventoryProvider: { inventoryProvider.next() }
        )

        _ = try await controller.inputDevices()
        _ = try await controller.inputDevices()
        XCTAssertEqual(inventoryProvider.callCount, 1)

        propertyListener.emit(
            objectID: 42,
            selector: kAudioDevicePropertyStreamConfiguration
        )
        _ = try await controller.inputDevices()

        XCTAssertEqual(inventoryProvider.callCount, 2)
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

private final class RecordingInventoryProvider: @unchecked Sendable {
    private let lock = NSLock()
    private let inventories: [CoreAudioDeviceInventory]
    private var calls = 0

    init(inventories: [CoreAudioDeviceInventory]) {
        precondition(!inventories.isEmpty)
        self.inventories = inventories
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    func next() -> CoreAudioDeviceInventory {
        lock.withLock {
            let inventory = inventories[min(calls, inventories.count - 1)]
            calls += 1
            return inventory
        }
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

    private struct Callback {
        let objectID: AudioObjectID
        let address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    private let lock = NSLock()
    private var recordedEvents: [Event] = []
    private var failedAddSelectors: Set<AudioObjectPropertySelector> = []
    private var failedRemoveStatuses: [AudioObjectPropertySelector: OSStatus] = [:]
    private var callbacks: [Callback] = []

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

    func emit(objectID: AudioObjectID, selector: AudioObjectPropertySelector) {
        let matchingCallbacks = lock.withLock {
            callbacks.filter {
                $0.objectID == objectID && $0.address.mSelector == selector
            }
        }
        for callback in matchingCallbacks {
            var address = callback.address
            withUnsafePointer(to: &address) { pointer in
                callback.block(1, pointer)
            }
        }
    }

    func addPropertyListener(
        objectID: AudioObjectID,
        address: inout AudioObjectPropertyAddress,
        queue: DispatchQueue,
        block: @escaping AudioObjectPropertyListenerBlock
    ) -> OSStatus {
        lock.withLock {
            recordedEvents.append(Event(kind: .add, selector: address.mSelector))
            guard !failedAddSelectors.contains(address.mSelector) else { return -1 }
            callbacks.append(Callback(objectID: objectID, address: address, block: block))
            return noErr
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
            let status = failedRemoveStatuses[address.mSelector] ?? noErr
            guard status == noErr else { return status }
            if let index = callbacks.firstIndex(where: {
                $0.objectID == objectID
                    && $0.address.mSelector == address.mSelector
                    && $0.address.mScope == address.mScope
                    && $0.address.mElement == address.mElement
            }) {
                callbacks.remove(at: index)
            }
            return noErr
        }
    }
}
