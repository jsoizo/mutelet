import CoreAudio
import XCTest
@testable import MuteletCore

@MainActor
final class MuteCoordinatorTests: XCTestCase {
    func testStartPublishesLiveDefaultInput() async {
        let audio = FakeAudioController(state: .live)
        let store = InMemoryReceiptStore()
        let coordinator = MuteCoordinator(audioController: audio, receiptStore: store)

        await coordinator.start()

        XCTAssertEqual(coordinator.status, .live(deviceName: "Test Input"))
    }

    func testToggleFromLiveMutesAndSavesOriginalValues() async {
        let audio = FakeAudioController(state: .live)
        let store = InMemoryReceiptStore()
        let coordinator = MuteCoordinator(audioController: audio, receiptStore: store)
        await coordinator.start()

        await coordinator.toggle()

        let muteCalls = await audio.muteCallCount()
        let storedReceipt = await store.receipt(deviceUID: FakeAudioController.uid)
        XCTAssertEqual(coordinator.status, .muted(deviceName: "Test Input"))
        XCTAssertEqual(muteCalls, 1)
        XCTAssertNotNil(storedReceipt)
    }

    func testReceiptIsSavedBeforeMutatingHardware() async {
        let audio = FakeAudioController(state: .live)
        let store = FaultInjectingReceiptStore(failsSave: true)
        let coordinator = MuteCoordinator(audioController: audio, receiptStore: store)
        await coordinator.start()

        await coordinator.toggle()

        let muteCalls = await audio.muteCallCount()
        XCTAssertEqual(muteCalls, 0)
        if case let .error(message) = coordinator.status {
            XCTAssertEqual(message, "The microphone could not be controlled.")
        } else {
            XCTFail("Expected a persistence error")
        }
    }

    func testToggleFromMutedRestoresAndRemovesReceipt() async throws {
        let receipt = FakeAudioController.originalReceipt
        let audio = FakeAudioController(state: .muted)
        let store = InMemoryReceiptStore()
        await store.save(receipt)
        let coordinator = MuteCoordinator(audioController: audio, receiptStore: store)
        await coordinator.start()

        await coordinator.toggle()

        let unmuteCalls = await audio.unmuteCallCount()
        let storedReceipt = await store.receipt(deviceUID: FakeAudioController.uid)
        XCTAssertEqual(coordinator.status, .live(deviceName: "Test Input"))
        XCTAssertEqual(unmuteCalls, 1)
        XCTAssertNil(storedReceipt)
    }

    func testToggleWaitsForInFlightOperationInsteadOfDroppingInput() async {
        let audio = FakeAudioController(state: .muted, suspendsUnmute: true)
        let store = InMemoryReceiptStore()
        await store.save(FakeAudioController.originalReceipt)
        let coordinator = MuteCoordinator(audioController: audio, receiptStore: store)
        await coordinator.start()

        let unmuteTask = Task {
            await coordinator.toggle()
        }
        await waitUntil { await audio.unmuteCallCount() == 1 }

        let remuteTask = Task {
            await coordinator.toggle()
        }
        await Task.yield()
        await audio.resumeUnmute()
        await unmuteTask.value
        await remuteTask.value

        let muteCalls = await audio.muteCallCount()
        XCTAssertEqual(muteCalls, 1)
        XCTAssertTrue(coordinator.hasToggleMuteIntent)
        XCTAssertEqual(coordinator.status, .muted(deviceName: "Test Input"))
    }

    func testQueuedRemuteInvalidatesRestorationFromPreviousToggle() async {
        let audio = FakeAudioController(state: .live, suspendsUnmute: true)
        let store = InMemoryReceiptStore()
        let coordinator = MuteCoordinator(audioController: audio, receiptStore: store)
        await coordinator.start()
        await coordinator.toggle()

        let unmuteTask = Task {
            await coordinator.toggle()
        }
        await waitUntil { await audio.unmuteCallCount() == 1 }
        let remuteTask = Task {
            await coordinator.toggle()
        }

        await audio.resumeUnmute()
        await unmuteTask.value
        await remuteTask.value
        try? await Task.sleep(for: .milliseconds(30))

        let receipt = await store.receipt(deviceUID: FakeAudioController.uid)
        XCTAssertTrue(coordinator.hasToggleMuteIntent)
        XCTAssertEqual(coordinator.status, .muted(deviceName: "Test Input"))
        XCTAssertNotNil(receipt)
    }

    func testToggleFromMixedChoosesMute() async {
        let audio = FakeAudioController(state: .mixed)
        let store = InMemoryReceiptStore()
        let coordinator = MuteCoordinator(audioController: audio, receiptStore: store)
        await coordinator.start()

        await coordinator.toggle()

        let muteCalls = await audio.muteCallCount()
        XCTAssertEqual(coordinator.status, .muted(deviceName: "Test Input"))
        XCTAssertEqual(muteCalls, 1)
    }

    func testMissingDefaultInputIsUnavailable() async {
        let audio = FakeAudioController(state: .live, hasDefaultInput: false)
        let store = InMemoryReceiptStore()
        let coordinator = MuteCoordinator(audioController: audio, receiptStore: store)

        await coordinator.start()

        XCTAssertEqual(coordinator.status, .unavailable)
        XCTAssertFalse(coordinator.status.canToggle)
    }

    func testPushToTalkMutesImmediatelyAndTracksPressAndRelease() async {
        let audio = FakeAudioController(state: .live)
        let store = InMemoryReceiptStore()
        let coordinator = MuteCoordinator(audioController: audio, receiptStore: store)
        await coordinator.start()

        await coordinator.setMode(.pushToTalk)

        let initialMuteCalls = await audio.muteCallCount()
        XCTAssertEqual(coordinator.mode, .pushToTalk)
        XCTAssertEqual(coordinator.status, .muted(deviceName: "Test Input"))
        XCTAssertEqual(initialMuteCalls, 1)

        await coordinator.handleHotKey(.pressed)
        await coordinator.handleHotKey(.pressed)

        let unmuteCalls = await audio.unmuteCallCount()
        XCTAssertEqual(coordinator.status, .live(deviceName: "Test Input"))
        XCTAssertEqual(unmuteCalls, 1)

        await coordinator.handleHotKey(.released)

        let finalMuteCalls = await audio.muteCallCount()
        XCTAssertEqual(coordinator.status, .muted(deviceName: "Test Input"))
        XCTAssertEqual(finalMuteCalls, 2)
    }

    func testModeSelectionIsPublishedBeforeTheSafetyMuteCompletes() async {
        let audio = FakeAudioController(state: .live)
        let store = InMemoryReceiptStore()
        let coordinator = MuteCoordinator(audioController: audio, receiptStore: store)
        await coordinator.start()

        let transition = coordinator.selectMode(.pushToTalk)

        XCTAssertEqual(coordinator.mode, .pushToTalk)
        await transition?.value
        XCTAssertEqual(coordinator.status, .muted(deviceName: "Test Input"))
    }

    func testPushToTalkRemutesAfterExternalUnmuteWhileNotPressed() async {
        let audio = FakeAudioController(state: .live)
        let store = InMemoryReceiptStore()
        let coordinator = MuteCoordinator(audioController: audio, receiptStore: store)
        await coordinator.start()
        await coordinator.setMode(.pushToTalk)

        await audio.simulateExternalState(.live)
        await waitUntil {
            await audio.muteCallCount() >= 2
                && coordinator.status == .muted(deviceName: "Test Input")
        }

        let muteCalls = await audio.muteCallCount()
        XCTAssertEqual(coordinator.status, .muted(deviceName: "Test Input"))
        XCTAssertEqual(muteCalls, 2)
    }

    func testControlEventBurstPerformsOneRefresh() async {
        let audio = FakeAudioController(state: .live)
        let coordinator = MuteCoordinator(
            audioController: audio,
            receiptStore: InMemoryReceiptStore()
        )
        await coordinator.start()
        let initialSnapshots = await audio.snapshotCallCount()

        await audio.simulateControlEvents(count: 5)
        await waitUntil { await audio.snapshotCallCount() > initialSnapshots }
        try? await Task.sleep(for: .milliseconds(30))

        let refreshedSnapshots = await audio.snapshotCallCount()
        XCTAssertEqual(refreshedSnapshots, initialSnapshots + 1)
    }

    func testStopWaitsForEventRefreshBeforeStartingANewGeneration() async {
        let audio = FakeAudioController(state: .live)
        let coordinator = MuteCoordinator(
            audioController: audio,
            receiptStore: InMemoryReceiptStore()
        )
        await coordinator.start()
        await audio.suspendNextSnapshot()
        await audio.simulateControlEvents(count: 1)
        await waitUntil { await audio.isSnapshotSuspended() }

        let stopCompletion = CompletionFlag()
        let stopTask = Task {
            await coordinator.stop()
            await stopCompletion.markCompleted()
        }
        try? await Task.sleep(for: .milliseconds(20))
        let stoppedWhileRefreshWasSuspended = await stopCompletion.isCompleted
        XCTAssertFalse(stoppedWhileRefreshWasSuspended)

        await audio.resumeSnapshot()
        await stopTask.value
        await coordinator.start()
        let snapshotsAfterRestart = await audio.snapshotCallCount()

        await audio.simulateControlEvents(count: 5)
        await waitUntil { await audio.snapshotCallCount() > snapshotsAfterRestart }
        try? await Task.sleep(for: .milliseconds(30))

        let refreshedSnapshots = await audio.snapshotCallCount()
        XCTAssertEqual(refreshedSnapshots, snapshotsAfterRestart + 1)
    }

    func testStopWaitsForInFlightStartupBeforeStartingANewGeneration() async {
        let audio = FakeAudioController(state: .live)
        let coordinator = MuteCoordinator(
            audioController: audio,
            receiptStore: InMemoryReceiptStore()
        )
        await audio.suspendNextEventsSetup()
        let startTask = Task { await coordinator.start() }
        await waitUntil { await audio.isEventsSetupSuspended() }

        let stopCompletion = CompletionFlag()
        let stopTask = Task {
            await coordinator.stop()
            await stopCompletion.markCompleted()
        }
        try? await Task.sleep(for: .milliseconds(20))
        let stoppedWhileStartupWasSuspended = await stopCompletion.isCompleted
        XCTAssertFalse(stoppedWhileStartupWasSuspended)

        await audio.resumeEventsSetup()
        await startTask.value
        await stopTask.value
        let staleStartupSnapshots = await audio.snapshotCallCount()
        XCTAssertEqual(staleStartupSnapshots, 0)

        await coordinator.start()
        let snapshotsAfterRestart = await audio.snapshotCallCount()
        await audio.simulateControlEvents(count: 5)
        await waitUntil { await audio.snapshotCallCount() > snapshotsAfterRestart }
        try? await Task.sleep(for: .milliseconds(30))

        let refreshedSnapshots = await audio.snapshotCallCount()
        XCTAssertEqual(refreshedSnapshots, snapshotsAfterRestart + 1)
    }

    func testControlEventForUnrelatedDeviceDoesNotRefresh() async {
        let audio = FakeAudioController(state: .live)
        let coordinator = MuteCoordinator(
            audioController: audio,
            receiptStore: InMemoryReceiptStore()
        )
        await coordinator.start()
        let initialSnapshots = await audio.snapshotCallCount()

        await audio.simulateControlEvents(count: 1, objectID: 999)
        try? await Task.sleep(for: .milliseconds(30))

        let refreshedSnapshots = await audio.snapshotCallCount()
        XCTAssertEqual(refreshedSnapshots, initialSnapshots)
    }

    func testPushToTalkDoesNotRemuteAnAlreadyMutedControlEvent() async {
        let audio = FakeAudioController(state: .live)
        let coordinator = MuteCoordinator(
            audioController: audio,
            receiptStore: InMemoryReceiptStore()
        )
        await coordinator.start()
        await coordinator.setMode(.pushToTalk)
        let initialSnapshots = await audio.snapshotCallCount()

        await audio.simulateControlEvents(count: 1)
        await waitUntil { await audio.snapshotCallCount() > initialSnapshots }

        let muteCalls = await audio.muteCallCount()
        XCTAssertEqual(muteCalls, 1)
    }

    func testPushToTalkReleaseForceMutesAfterReceiptRemovalFailure() async {
        let audio = FakeAudioController(state: .live)
        let store = FaultInjectingReceiptStore(failsRemoval: true)
        let coordinator = MuteCoordinator(audioController: audio, receiptStore: store)
        await coordinator.start()
        await coordinator.setMode(.pushToTalk)

        await coordinator.handleHotKey(.pressed)
        if case let .error(message) = coordinator.status {
            XCTAssertEqual(message, "The microphone could not be controlled.")
        } else {
            XCTFail("Expected a receipt removal error")
        }

        await coordinator.handleHotKey(.released)

        let muteCalls = await audio.muteCallCount()
        XCTAssertEqual(muteCalls, 2)
        XCTAssertEqual(coordinator.status, .muted(deviceName: "Test Input"))
    }

    func testStoppingPushToTalkForceMutesBeforeExternalEventIsHandled() async {
        let audio = FakeAudioController(state: .live)
        let coordinator = MuteCoordinator(
            audioController: audio,
            receiptStore: InMemoryReceiptStore()
        )
        await coordinator.start()
        await coordinator.setMode(.pushToTalk)

        await audio.setStateWithoutEvent(.live)
        await coordinator.stop()

        let muteCalls = await audio.muteCallCount()
        XCTAssertEqual(muteCalls, 2)
        XCTAssertEqual(coordinator.status, .muted(deviceName: "Test Input"))
    }

    func testChangingModeWhilePressedDiscardsThePendingRelease() async {
        let audio = FakeAudioController(state: .live)
        let store = InMemoryReceiptStore()
        let coordinator = MuteCoordinator(audioController: audio, receiptStore: store)
        await coordinator.start()
        await coordinator.setMode(.pushToTalk)
        await coordinator.handleHotKey(.pressed)

        await coordinator.setMode(.toggle)
        await coordinator.handleHotKey(.released)

        let muteCalls = await audio.muteCallCount()
        let unmuteCalls = await audio.unmuteCallCount()
        XCTAssertEqual(coordinator.mode, .toggle)
        XCTAssertEqual(coordinator.status, .muted(deviceName: "Test Input"))
        XCTAssertEqual(muteCalls, 2)
        XCTAssertEqual(unmuteCalls, 1)
    }

    func testCancellingActivePushToTalkGestureRemutes() async {
        let audio = FakeAudioController(state: .live)
        let coordinator = MuteCoordinator(
            audioController: audio,
            receiptStore: InMemoryReceiptStore()
        )
        await coordinator.start()
        await coordinator.setMode(.pushToTalk)
        await coordinator.handleHotKey(.pressed)

        let cancelledSafely = await coordinator.cancelActiveHotKeyGesture()

        XCTAssertTrue(cancelledSafely)
        XCTAssertEqual(coordinator.status, .muted(deviceName: "Test Input"))
        let muteCalls = await audio.muteCallCount()
        XCTAssertEqual(muteCalls, 2)
    }

    func testStoppingWhilePushToTalkIsPressedMutesBeforeStopping() async {
        let audio = FakeAudioController(state: .live)
        let store = InMemoryReceiptStore()
        let coordinator = MuteCoordinator(audioController: audio, receiptStore: store)
        await coordinator.start()
        await coordinator.setMode(.pushToTalk)
        await coordinator.handleHotKey(.pressed)

        await coordinator.stop()

        let muteCalls = await audio.muteCallCount()
        XCTAssertEqual(coordinator.status, .muted(deviceName: "Test Input"))
        XCTAssertEqual(muteCalls, 2)
    }

    func testStoppingWaitsForAnInFlightUnmuteBeforeRemuting() async {
        let audio = FakeAudioController(state: .live, suspendsUnmute: true)
        let store = InMemoryReceiptStore()
        let coordinator = MuteCoordinator(audioController: audio, receiptStore: store)
        await coordinator.start()
        await coordinator.setMode(.pushToTalk)

        let pressTask = Task {
            await coordinator.handleHotKey(.pressed)
        }
        for _ in 0..<100 where await audio.unmuteCallCount() == 0 {
            await Task.yield()
        }

        let stopTask = Task {
            await coordinator.stop()
        }
        await Task.yield()
        await audio.resumeUnmute()
        await pressTask.value
        await stopTask.value

        let muteCalls = await audio.muteCallCount()
        XCTAssertEqual(coordinator.status, .muted(deviceName: "Test Input"))
        XCTAssertEqual(muteCalls, 2)
    }

    func testAllInputsAggregatesMixedStateAndMutesEveryDevice() async {
        let audio = MultiDeviceAudioController(
            states: ["built-in": .live, "usb": .muted],
            defaultUID: "built-in"
        )
        let coordinator = MuteCoordinator(
            audioController: audio,
            receiptStore: InMemoryReceiptStore()
        )
        await coordinator.start()

        await coordinator.selectTarget(.allInputs)

        XCTAssertEqual(coordinator.status, .mixed(deviceName: "All Inputs"))

        await coordinator.toggle()

        let mutedUIDs = await audio.mutedUIDs()
        XCTAssertEqual(coordinator.status, .muted(deviceName: "All Inputs"))
        XCTAssertEqual(mutedUIDs, ["built-in"])
    }

    func testSpecificDeviceReconnectsByUID() async {
        let audio = MultiDeviceAudioController(
            states: ["built-in": .live, "usb": .live],
            defaultUID: "built-in",
            names: ["usb": "USB Mic"]
        )
        let coordinator = MuteCoordinator(
            audioController: audio,
            receiptStore: InMemoryReceiptStore()
        )
        await coordinator.start()
        await coordinator.selectTarget(.device(uid: "usb", name: "USB Mic"))

        await audio.disconnect(uid: "usb")
        await waitUntil { coordinator.status == .disconnected(deviceName: "USB Mic") }

        await audio.connect(uid: "usb", state: .live)
        await waitUntil { coordinator.status == .live(deviceName: "USB Mic") }

        XCTAssertEqual(coordinator.target, .device(uid: "usb", name: "USB Mic"))
    }

    func testSpecificDeviceReconnectIsRemutedWhileIntentIsActive() async {
        let audio = MultiDeviceAudioController(
            states: ["built-in": .live, "usb": .live],
            defaultUID: "built-in",
            names: ["usb": "USB Mic"]
        )
        let coordinator = MuteCoordinator(
            audioController: audio,
            receiptStore: InMemoryReceiptStore()
        )
        await coordinator.start()
        await coordinator.selectTarget(.device(uid: "usb", name: "USB Mic"))
        await coordinator.toggle()

        await audio.disconnect(uid: "usb")
        await waitUntil { coordinator.status == .disconnected(deviceName: "USB Mic") }
        await audio.connect(uid: "usb", state: .live)
        await waitUntil {
            coordinator.status == .muted(deviceName: "USB Mic")
        }

        XCTAssertEqual(coordinator.status, .muted(deviceName: "USB Mic"))
    }

    func testDisconnectedToggleIntentCanBeCancelledBeforeReconnect() async {
        let audio = MultiDeviceAudioController(
            states: ["usb": .live],
            defaultUID: "usb",
            names: ["usb": "USB Mic"]
        )
        let store = InMemoryReceiptStore()
        let coordinator = MuteCoordinator(
            audioController: audio,
            receiptStore: store
        )
        await coordinator.start()
        await coordinator.toggle()
        await audio.disconnect(uid: "usb")
        await waitUntil {
            coordinator.status == .unavailable && !coordinator.isBusy
        }

        XCTAssertTrue(coordinator.canToggle)
        await coordinator.toggle()
        XCTAssertFalse(coordinator.hasToggleMuteIntent)

        await audio.connect(uid: "usb", state: .muted)
        await waitUntil {
            let state = await audio.state(uid: "usb")
            let receipt = await store.receipt(deviceUID: "usb")
            return state == .live && receipt == nil
        }
        let reconnectedState = await audio.state(uid: "usb")
        let removedReceipt = await store.receipt(deviceUID: "usb")
        XCTAssertEqual(reconnectedState, .live)
        XCTAssertNil(removedReceipt)
    }

    func testSuspendAndResumeRetainsToggleIntent() async {
        let audio = MultiDeviceAudioController(
            states: ["built-in": .live],
            defaultUID: "built-in"
        )
        let coordinator = MuteCoordinator(
            audioController: audio,
            receiptStore: InMemoryReceiptStore()
        )
        await coordinator.start()
        await coordinator.toggle()
        await coordinator.suspend()
        await audio.setStateWithoutEvent(uid: "built-in", state: .live)

        await coordinator.resume()

        let resumedState = await audio.state(uid: "built-in")
        XCTAssertEqual(resumedState, .muted)
        XCTAssertEqual(coordinator.status, .muted(deviceName: "built-in"))
    }

    func testAllInputsMutesNewDeviceWhileMuteLatchIsActive() async {
        let audio = MultiDeviceAudioController(
            states: ["built-in": .live],
            defaultUID: "built-in"
        )
        let coordinator = MuteCoordinator(
            audioController: audio,
            receiptStore: InMemoryReceiptStore()
        )
        await coordinator.start()
        await coordinator.selectTarget(.allInputs)
        await coordinator.toggle()

        await audio.connect(uid: "usb", state: .live)
        await waitUntil {
            let state = await audio.state(uid: "usb")
            return state == .muted
                && coordinator.status == .muted(deviceName: "All Inputs")
        }

        XCTAssertEqual(coordinator.status, .muted(deviceName: "All Inputs"))
    }

    func testAllInputsMutesNewDeviceWhileMaintenancePreferenceIsDisabled() async {
        let audio = MultiDeviceAudioController(
            states: ["built-in": .live],
            defaultUID: "built-in"
        )
        let coordinator = MuteCoordinator(
            audioController: audio,
            receiptStore: InMemoryReceiptStore()
        )
        coordinator.configure(
            mode: .toggle,
            target: .allInputs,
            maintainsMuteOnInputChange: false
        )
        await coordinator.start()
        await coordinator.toggle()

        await audio.connect(uid: "usb", state: .live)
        await waitUntil {
            await audio.state(uid: "usb") == .muted
                && coordinator.status == .muted(deviceName: "All Inputs")
        }

        let usbState = await audio.state(uid: "usb")
        XCTAssertEqual(usbState, .muted)
    }

    func testAllInputsMuteLatchSurvivesPushToTalkRoundTrip() async {
        let audio = MultiDeviceAudioController(
            states: ["built-in": .live],
            defaultUID: "built-in"
        )
        let coordinator = MuteCoordinator(
            audioController: audio,
            receiptStore: InMemoryReceiptStore()
        )
        await coordinator.start()
        await coordinator.selectTarget(.allInputs)
        await coordinator.toggle()
        await coordinator.setMode(.pushToTalk)
        await coordinator.setMode(.toggle)

        await audio.connect(uid: "usb", state: .live)
        await waitUntil {
            await audio.state(uid: "usb") == .muted
                && coordinator.status == .muted(deviceName: "All Inputs")
        }

        let usbState = await audio.state(uid: "usb")
        XCTAssertEqual(usbState, .muted)
    }

    func testDefaultInputChangeMutesNewDefaultThenRestoresPreviousInput() async {
        let audio = MultiDeviceAudioController(
            states: ["built-in": .live, "usb": .live],
            defaultUID: "built-in",
            names: ["built-in": "Built-in", "usb": "USB Mic"]
        )
        let store = InMemoryReceiptStore()
        let coordinator = MuteCoordinator(audioController: audio, receiptStore: store)
        await coordinator.start()
        await coordinator.toggle()

        await audio.changeDefault(to: "usb")
        await waitUntil {
            let usb = await audio.state(uid: "usb")
            let builtIn = await audio.state(uid: "built-in")
            let builtInReceipt = await store.receipt(deviceUID: "built-in")
            return usb == .muted
                && builtIn == .live
                && builtInReceipt == nil
                && coordinator.status == .muted(deviceName: "USB Mic")
        }

        XCTAssertEqual(coordinator.status, .muted(deviceName: "USB Mic"))
        let builtInReceipt = await store.receipt(deviceUID: "built-in")
        let usbReceipt = await store.receipt(deviceUID: "usb")
        XCTAssertNil(builtInReceipt)
        XCTAssertNotNil(usbReceipt)
    }

    func testMuteCompletedAfterGenerationChangeIsRestoredInsteadOfOrphaned() async {
        let audio = MultiDeviceAudioController(
            states: ["built-in": .live, "usb": .live, "wireless": .live],
            defaultUID: "built-in"
        )
        let store = InMemoryReceiptStore()
        let coordinator = MuteCoordinator(
            audioController: audio,
            receiptStore: store,
            maintenanceSleep: { _ in }
        )
        await coordinator.start()
        await coordinator.toggle()
        await audio.suspendNextMute(uid: "usb")

        await audio.changeDefault(to: "usb")
        await waitUntil { await audio.isMuteSuspended() }
        await audio.changeDefault(to: "wireless")
        await audio.resumeMute()

        await waitUntil {
            let builtIn = await audio.state(uid: "built-in")
            let usb = await audio.state(uid: "usb")
            let wireless = await audio.state(uid: "wireless")
            let builtInReceipt = await store.receipt(deviceUID: "built-in")
            let usbReceipt = await store.receipt(deviceUID: "usb")
            let wirelessReceipt = await store.receipt(deviceUID: "wireless")
            return builtIn == .live
                && usb == .live
                && wireless == .muted
                && builtInReceipt == nil
                && usbReceipt == nil
                && wirelessReceipt != nil
        }

        let usbState = await audio.state(uid: "usb")
        let usbReceipt = await store.receipt(deviceUID: "usb")
        XCTAssertEqual(usbState, .live)
        XCTAssertNil(usbReceipt)
    }

    func testTargetReturningDuringPendingRestoreIsRemutedBeforeReceiptRemoval() async {
        let operations = OperationRecorder()
        let audio = MultiDeviceAudioController(
            states: ["built-in": .live, "usb": .live],
            defaultUID: "built-in",
            names: ["built-in": "Built-in", "usb": "USB Mic"],
            operationRecorder: operations
        )
        let store = InMemoryReceiptStore(operationRecorder: operations)
        let coordinator = MuteCoordinator(
            audioController: audio,
            receiptStore: store,
            maintenanceSleep: { _ in }
        )
        await coordinator.start()
        await coordinator.toggle()
        await operations.reset()
        await audio.suspendNextUnmute(uid: "built-in")

        await audio.changeDefault(to: "usb")
        await waitUntil { await audio.isUnmuteSuspended() }
        await audio.changeDefault(to: "built-in")
        await audio.resumeUnmute()

        await waitUntil {
            let state = await audio.state(uid: "built-in")
            let receipt = await store.receipt(deviceUID: "built-in")
            return state == .muted && receipt != nil
        }

        let builtInState = await audio.state(uid: "built-in")
        let builtInReceipt = await store.receipt(deviceUID: "built-in")
        XCTAssertEqual(builtInState, .muted)
        XCTAssertNotNil(builtInReceipt)

        let recordedOperations = await operations.values()
        guard let unmuteIndex = recordedOperations.firstIndex(
            of: "audio.unmute:built-in"
        ),
        let remuteIndex = recordedOperations.indices.first(where: {
            $0 > unmuteIndex && recordedOperations[$0] == "audio.mute:built-in"
        }) else {
            XCTFail("Expected the restored current target to be remuted")
            return
        }
        XCTAssertLessThan(unmuteIndex, remuteIndex)
        XCTAssertFalse(
            recordedOperations[unmuteIndex...remuteIndex].contains(
                "receipt.remove:built-in"
            )
        )
        XCTAssertFalse(recordedOperations.contains("receipt.remove:built-in"))
    }

    func testFailedPreviousInputRestorationIsRetriedAndRemainsVisible() async {
        let audio = MultiDeviceAudioController(
            states: ["built-in": .live, "usb": .live],
            defaultUID: "built-in",
            names: ["built-in": "Built-in", "usb": "USB Mic"]
        )
        let store = InMemoryReceiptStore()
        let coordinator = MuteCoordinator(
            audioController: audio,
            receiptStore: store,
            maintenanceSleep: { _ in }
        )
        await coordinator.start()
        await coordinator.toggle()
        await audio.setUnmuteFailures(uid: "built-in", count: 4)

        await audio.changeDefault(to: "usb")
        await waitUntil { !coordinator.restorationWarnings.isEmpty }

        let usbStateAfterFailure = await audio.state(uid: "usb")
        let builtInStateAfterFailure = await audio.state(uid: "built-in")
        let retainedReceipt = await store.receipt(deviceUID: "built-in")
        XCTAssertEqual(usbStateAfterFailure, .muted)
        XCTAssertEqual(builtInStateAfterFailure, .muted)
        XCTAssertEqual(
            coordinator.restorationWarnings,
            [RestorationWarningItem(deviceUID: "built-in", deviceName: "Built-in")]
        )
        XCTAssertNotNil(retainedReceipt)

        await audio.setUnmuteFailures(uid: "built-in", count: 0)
        await coordinator.toggle()
        await waitUntil { coordinator.restorationWarnings.isEmpty }

        let restoredState = await audio.state(uid: "built-in")
        let currentState = await audio.state(uid: "usb")
        let removedReceipt = await store.receipt(deviceUID: "built-in")
        XCTAssertEqual(restoredState, .live)
        XCTAssertEqual(currentState, .live)
        XCTAssertNil(removedReceipt)
        XCTAssertEqual(coordinator.status, .live(deviceName: "USB Mic"))
    }

    func testPushToTalkRestoresDisconnectedPendingInputAfterReconnect() async {
        let audio = MultiDeviceAudioController(
            states: ["built-in": .live, "usb": .live],
            defaultUID: "built-in",
            names: ["built-in": "Built-in", "usb": "USB Mic"]
        )
        let coordinator = MuteCoordinator(
            audioController: audio,
            receiptStore: InMemoryReceiptStore(),
            maintenanceSleep: { _ in }
        )
        await coordinator.start()
        await coordinator.toggle()
        await audio.setUnmuteFailures(uid: "built-in", count: 4)
        await audio.changeDefault(to: "usb")
        await waitUntil { !coordinator.restorationWarnings.isEmpty }
        await audio.disconnect(uid: "built-in")
        await audio.setUnmuteFailures(uid: "built-in", count: 0)

        await coordinator.setMode(.pushToTalk)
        await audio.connect(uid: "built-in", state: .muted)
        await waitUntil { await audio.state(uid: "built-in") == .live }

        let currentState = await audio.state(uid: "usb")
        XCTAssertEqual(currentState, .muted)
        XCTAssertTrue(coordinator.restorationWarnings.isEmpty)
    }

    func testPushToTalkDefaultChangeMutesNewInputBeforeRestoringPreviousInput() async {
        let audio = MultiDeviceAudioController(
            states: ["built-in": .live, "usb": .live],
            defaultUID: "built-in",
            names: ["built-in": "Built-in", "usb": "USB Mic"]
        )
        let store = InMemoryReceiptStore()
        let coordinator = MuteCoordinator(
            audioController: audio,
            receiptStore: store,
            maintenanceSleep: { _ in }
        )
        coordinator.configure(mode: .pushToTalk, target: .systemDefault)
        await coordinator.start()

        await audio.changeDefault(to: "usb")
        await waitUntil {
            let builtIn = await audio.state(uid: "built-in")
            let usb = await audio.state(uid: "usb")
            let builtInReceipt = await store.receipt(deviceUID: "built-in")
            let usbReceipt = await store.receipt(deviceUID: "usb")
            return builtIn == .live
                && usb == .muted
                && builtInReceipt == nil
                && usbReceipt != nil
        }

        let builtInState = await audio.state(uid: "built-in")
        let usbState = await audio.state(uid: "usb")
        XCTAssertEqual(builtInState, .live)
        XCTAssertEqual(usbState, .muted)
    }

    func testPushToTalkKeepsOldInputMutedWhenCurrentSafetyMuteFails() async {
        let audio = MultiDeviceAudioController(
            states: ["built-in": .live, "usb": .live],
            defaultUID: "built-in",
            names: ["built-in": "Built-in", "usb": "USB Mic"]
        )
        let store = InMemoryReceiptStore()
        let coordinator = MuteCoordinator(
            audioController: audio,
            receiptStore: store,
            maintenanceSleep: { _ in }
        )
        await coordinator.start()
        await coordinator.toggle()
        await audio.setMuteFailures(uid: "usb", count: 4)
        await audio.changeDefault(to: "usb")
        await waitUntil {
            if case .error = coordinator.status { return true }
            return false
        }
        await audio.setMuteFailures(uid: "usb", count: 4)

        await coordinator.setMode(.pushToTalk)

        let oldState = await audio.state(uid: "built-in")
        let oldReceipt = await store.receipt(deviceUID: "built-in")
        XCTAssertEqual(oldState, .muted)
        XCTAssertNotNil(oldReceipt)
    }

    func testPushToTalkTargetChangeStopsWhenCurrentTargetIsUnsupported() async {
        let audio = MultiDeviceAudioController(
            states: ["unsupported": .unsupported, "usb": .live],
            defaultUID: "unsupported",
            names: ["usb": "USB Mic"]
        )
        let coordinator = MuteCoordinator(
            audioController: audio,
            receiptStore: InMemoryReceiptStore()
        )
        await coordinator.start()
        await coordinator.setMode(.pushToTalk)

        await coordinator.selectTarget(.device(uid: "usb", name: "USB Mic"))

        XCTAssertEqual(coordinator.target, .systemDefault)
        let usbState = await audio.state(uid: "usb")
        XCTAssertEqual(usbState, .live)
    }

    func testSelectingCurrentTargetCancelsInFlightTargetChange() async {
        let audio = MultiDeviceAudioController(
            states: ["built-in": .live, "usb": .live],
            defaultUID: "built-in",
            names: ["usb": "USB Mic"]
        )
        let coordinator = MuteCoordinator(
            audioController: audio,
            receiptStore: InMemoryReceiptStore()
        )
        await coordinator.start()
        await audio.suspendNextInputDevices()
        let selection = Task {
            await coordinator.selectTarget(.device(uid: "usb", name: "USB Mic"))
        }
        await waitUntil { await audio.isInputDevicesSuspended() }

        await coordinator.selectTarget(.systemDefault)
        await audio.resumeInputDevices()
        await selection.value

        XCTAssertEqual(coordinator.target, .systemDefault)
    }

    func testExplicitTargetChangeRestoresReceiptFromPreviousSession() async {
        let audio = MultiDeviceAudioController(
            states: ["built-in": .muted, "usb": .live],
            defaultUID: "built-in",
            names: ["built-in": "Built-in", "usb": "USB Mic"]
        )
        let store = InMemoryReceiptStore()
        await store.save(
            AudioMutationReceipt(
                deviceUID: "built-in",
                originalValues: [
                    AudioControlValue(
                        control: AudioControl(
                            kind: .mute,
                            element: kAudioObjectPropertyElementMain
                        ),
                        value: 0
                    ),
                    AudioControlValue(
                        control: AudioControl(
                            kind: .volume,
                            element: kAudioObjectPropertyElementMain
                        ),
                        value: 0.7
                    ),
                ]
            )
        )
        let coordinator = MuteCoordinator(audioController: audio, receiptStore: store)
        await coordinator.start()
        await coordinator.selectTarget(.device(uid: "usb", name: "USB Mic"))

        let previousSessionState = await audio.state(uid: "built-in")
        let previousSessionReceipt = await store.receipt(deviceUID: "built-in")
        XCTAssertEqual(previousSessionState, .live)
        XCTAssertNil(previousSessionReceipt)
    }

    func testResumeRetriesPendingRestorationForDeviceReconnectedDuringSleep() async {
        let audio = MultiDeviceAudioController(
            states: ["built-in": .live, "usb": .live],
            defaultUID: "built-in",
            names: ["built-in": "Built-in", "usb": "USB Mic"]
        )
        let coordinator = MuteCoordinator(
            audioController: audio,
            receiptStore: InMemoryReceiptStore(),
            maintenanceSleep: { _ in }
        )
        await coordinator.start()
        await coordinator.toggle()
        await audio.setUnmuteFailures(uid: "built-in", count: 4)
        await audio.changeDefault(to: "usb")
        await waitUntil { !coordinator.restorationWarnings.isEmpty }
        await audio.disconnect(uid: "built-in")
        await coordinator.toggle()
        XCTAssertFalse(coordinator.hasToggleMuteIntent)
        await coordinator.suspend()
        await audio.setUnmuteFailures(uid: "built-in", count: 0)
        await audio.connect(uid: "built-in", state: .muted)

        await coordinator.resume()
        await waitUntil { await audio.state(uid: "built-in") == .live }

        XCTAssertTrue(coordinator.restorationWarnings.isEmpty)
    }

    func testToggleIntentRemutesAfterExternalUnmute() async {
        let audio = MultiDeviceAudioController(
            states: ["built-in": .live],
            defaultUID: "built-in"
        )
        let coordinator = MuteCoordinator(
            audioController: audio,
            receiptStore: InMemoryReceiptStore()
        )
        await coordinator.start()
        await coordinator.toggle()

        await audio.simulateExternalState(uid: "built-in", state: .live)
        await waitUntil {
            await audio.state(uid: "built-in") == .muted
                && coordinator.status == .muted(deviceName: "built-in")
        }

        XCTAssertEqual(coordinator.status, .muted(deviceName: "built-in"))
        let attempts = await audio.muteAttemptCount(uid: "built-in")
        XCTAssertGreaterThanOrEqual(attempts, 2)
    }

    func testDisablingMaintenanceStopsExternalRemuteWithoutUnmutingImmediately() async {
        let audio = MultiDeviceAudioController(
            states: ["built-in": .live],
            defaultUID: "built-in"
        )
        let coordinator = MuteCoordinator(
            audioController: audio,
            receiptStore: InMemoryReceiptStore()
        )
        await coordinator.start()
        await coordinator.toggle()

        await coordinator.setMaintainsMuteOnInputChange(false)
        let stateBeforeExternalChange = await audio.state(uid: "built-in")
        XCTAssertEqual(stateBeforeExternalChange, .muted)
        await audio.simulateExternalState(uid: "built-in", state: .live)
        try? await Task.sleep(for: .milliseconds(30))

        let stateAfterExternalChange = await audio.state(uid: "built-in")
        XCTAssertEqual(stateAfterExternalChange, .live)
    }

    func testStaleEnableCannotRestoreIntentAfterSettingIsDisabledAgain() async {
        let audio = FakeAudioController(state: .live)
        let coordinator = MuteCoordinator(
            audioController: audio,
            receiptStore: InMemoryReceiptStore()
        )
        await coordinator.start()
        await coordinator.toggle()
        await coordinator.setMaintainsMuteOnInputChange(false)
        await audio.suspendNextSnapshot()

        let enableTask = Task {
            await coordinator.setMaintainsMuteOnInputChange(true)
        }
        await waitUntil { await audio.isSnapshotSuspended() }
        let disableTask = Task {
            await coordinator.setMaintainsMuteOnInputChange(false)
        }
        await disableTask.value
        await audio.resumeSnapshot()
        await enableTask.value

        XCTAssertFalse(coordinator.hasToggleMuteIntent)
    }

    func testReconnectMuteRetriesWithInjectedSleeper() async {
        let audio = MultiDeviceAudioController(
            states: ["built-in": .live],
            defaultUID: "built-in"
        )
        let sleeps = DurationRecorder()
        let coordinator = MuteCoordinator(
            audioController: audio,
            receiptStore: InMemoryReceiptStore(),
            maintenanceSleep: { duration in await sleeps.record(duration) }
        )
        await coordinator.start()
        await coordinator.toggle()
        await audio.setMuteFailures(uid: "built-in", count: 2)
        await audio.simulateExternalState(uid: "built-in", state: .live)

        await waitUntil {
            await audio.state(uid: "built-in") == .muted
                && coordinator.status == .muted(deviceName: "built-in")
        }

        let recordedSleeps = await sleeps.values()
        XCTAssertEqual(recordedSleeps, [.milliseconds(100), .milliseconds(300)])
        XCTAssertEqual(coordinator.status, .muted(deviceName: "built-in"))
    }

    func testTransientUnsupportedInventoryIsRetriedWithoutAnotherEvent() async {
        let audio = MultiDeviceAudioController(
            states: ["built-in": .live],
            defaultUID: "built-in"
        )
        let sleeps = DurationRecorder()
        let coordinator = MuteCoordinator(
            audioController: audio,
            receiptStore: InMemoryReceiptStore(),
            maintenanceSleep: { duration in await sleeps.record(duration) }
        )
        await coordinator.start()
        await coordinator.toggle()
        await audio.setTransientUnsupportedInventories(2)

        await audio.simulateExternalState(uid: "built-in", state: .live)
        await waitUntil {
            await audio.state(uid: "built-in") == .muted
                && coordinator.status == .muted(deviceName: "built-in")
        }

        let recordedSleeps = await sleeps.values()
        XCTAssertEqual(recordedSleeps, [.milliseconds(100)])
        XCTAssertEqual(coordinator.status, .muted(deviceName: "built-in"))
    }

    func testDisablingDuringRetryCancelsRemainingMuteAttempts() async {
        let audio = MultiDeviceAudioController(
            states: ["built-in": .live],
            defaultUID: "built-in"
        )
        let coordinator = MuteCoordinator(
            audioController: audio,
            receiptStore: InMemoryReceiptStore()
        )
        await coordinator.start()
        await coordinator.toggle()
        await audio.setMuteFailures(uid: "built-in", count: 4)
        await audio.simulateExternalState(uid: "built-in", state: .live)
        await waitUntil { await audio.muteAttemptCount(uid: "built-in") == 2 }

        await coordinator.setMaintainsMuteOnInputChange(false)
        try? await Task.sleep(for: .milliseconds(700))

        let attempts = await audio.muteAttemptCount(uid: "built-in")
        let state = await audio.state(uid: "built-in")
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(state, .live)
    }

    func testToggleTargetChangeRestoresManagedPreviousTarget() async {
        let audio = MultiDeviceAudioController(
            states: ["built-in": .live, "usb": .live],
            defaultUID: "built-in",
            names: ["usb": "USB Mic"]
        )
        let store = InMemoryReceiptStore()
        let coordinator = MuteCoordinator(audioController: audio, receiptStore: store)
        await coordinator.start()
        await coordinator.toggle()

        await coordinator.selectTarget(.device(uid: "usb", name: "USB Mic"))

        let builtInState = await audio.state(uid: "built-in")
        let builtInReceipt = await store.receipt(deviceUID: "built-in")
        XCTAssertEqual(builtInState, .live)
        XCTAssertNil(builtInReceipt)
        XCTAssertEqual(coordinator.target, .device(uid: "usb", name: "USB Mic"))
    }

    func testPushToTalkTargetChangeRestoresOldAndMutesNewTarget() async {
        let audio = MultiDeviceAudioController(
            states: ["built-in": .live, "usb": .live],
            defaultUID: "built-in",
            names: ["usb": "USB Mic"]
        )
        let store = InMemoryReceiptStore()
        let coordinator = MuteCoordinator(audioController: audio, receiptStore: store)
        await coordinator.start()
        await coordinator.setMode(.pushToTalk)

        await coordinator.selectTarget(.device(uid: "usb", name: "USB Mic"))

        let builtInState = await audio.state(uid: "built-in")
        let usbState = await audio.state(uid: "usb")
        let builtInReceipt = await store.receipt(deviceUID: "built-in")
        let usbReceipt = await store.receipt(deviceUID: "usb")
        XCTAssertEqual(builtInState, .live)
        XCTAssertEqual(usbState, .muted)
        XCTAssertNil(builtInReceipt)
        XCTAssertNotNil(usbReceipt)
    }

    func testAllInputsReportsUnsupportedDeviceAsPartial() async {
        let audio = MultiDeviceAudioController(
            states: ["built-in": .muted, "virtual": .unsupported],
            defaultUID: "built-in"
        )
        let coordinator = MuteCoordinator(
            audioController: audio,
            receiptStore: InMemoryReceiptStore()
        )
        await coordinator.start()

        await coordinator.selectTarget(.allInputs)

        XCTAssertEqual(
            coordinator.status,
            .partial(
                deviceName: "All Inputs",
                muted: 1,
                live: 0,
                mixed: 0,
                unsupported: 1,
                failed: 0
            )
        )
        XCTAssertTrue(coordinator.status.canToggle)
        XCTAssertFalse(coordinator.status.isMuted)
    }

    func testVolumeOnlyTargetPublishesSilenceWarning() async {
        let audio = MultiDeviceAudioController(
            states: ["usb": .live],
            defaultUID: "usb",
            names: ["usb": "Volume-only USB"],
            volumeOnlyUIDs: ["usb"]
        )
        let coordinator = MuteCoordinator(
            audioController: audio,
            receiptStore: InMemoryReceiptStore()
        )

        await coordinator.start()

        XCTAssertEqual(
            coordinator.targetWarning,
            "Volume-only mute may not guarantee complete silence."
        )
    }

    func testUnverifiedRestorationKeepsReceipt() async {
        let receipt = FakeAudioController.originalReceipt
        let audio = FakeAudioController(state: .muted, restoresIncorrectly: true)
        let store = InMemoryReceiptStore()
        await store.save(receipt)
        let coordinator = MuteCoordinator(audioController: audio, receiptStore: store)
        await coordinator.start()

        await coordinator.toggle()

        let retainedReceipt = await store.receipt(deviceUID: FakeAudioController.uid)
        XCTAssertNotNil(retainedReceipt)
        if case let .error(message) = coordinator.status {
            XCTAssertEqual(message, "The microphone could not be controlled.")
        } else {
            XCTFail("Expected incomplete restoration error")
        }
    }

    func testChangedControlTopologyDiscardsStaleReceiptAndAllowsRecovery() async {
        let audio = MultiDeviceAudioController(
            states: ["built-in": .muted],
            defaultUID: "built-in",
            names: ["built-in": "Built-in"]
        )
        let store = InMemoryReceiptStore()
        await store.save(
            AudioMutationReceipt(
                deviceUID: "built-in",
                originalValues: [
                    AudioControlValue(
                        control: AudioControl(
                            kind: .mute,
                            element: kAudioObjectPropertyElementMain
                        ),
                        value: 0
                    ),
                ]
            )
        )
        await audio.setRestorationTopologyChanged(uid: "built-in", changed: true)
        let coordinator = MuteCoordinator(audioController: audio, receiptStore: store)
        await coordinator.start()

        await coordinator.toggle()

        let discardedReceipt = await store.receipt(deviceUID: "built-in")
        XCTAssertNil(discardedReceipt)
        XCTAssertEqual(
            coordinator.restorationWarnings,
            [RestorationWarningItem(deviceUID: "built-in", deviceName: "Built-in")]
        )

        await audio.setRestorationTopologyChanged(uid: "built-in", changed: false)
        await coordinator.refresh()
        await coordinator.toggle()
        let recoveredState = await audio.state(uid: "built-in")
        XCTAssertEqual(recoveredState, .live)
    }

    func testStaleSnapshotRollsBackNewReceiptBeforeAnyMutation() async {
        let audio = MultiDeviceAudioController(
            states: ["built-in": .live],
            defaultUID: "built-in"
        )
        let store = InMemoryReceiptStore()
        let coordinator = MuteCoordinator(audioController: audio, receiptStore: store)
        await coordinator.start()
        await audio.setStaleMuteFailures(uid: "built-in", count: 1)

        await coordinator.toggle()

        let receipt = await store.receipt(deviceUID: "built-in")
        let state = await audio.state(uid: "built-in")
        XCTAssertNil(receipt)
        XCTAssertEqual(state, .live)
    }

    func testStaleSnapshotRollsBackExpandedReceipt() async {
        let mute = AudioControl(kind: .mute, element: kAudioObjectPropertyElementMain)
        let volume = AudioControl(kind: .volume, element: kAudioObjectPropertyElementMain)
        let originalReceipt = AudioMutationReceipt(
            deviceUID: "built-in",
            originalValues: [
                AudioControlValue(control: mute, value: 0),
                AudioControlValue(control: volume, value: 0.7),
            ]
        )
        let audio = MultiDeviceAudioController(
            states: ["built-in": .live],
            defaultUID: "built-in",
            expandedTopologyUIDs: ["built-in"]
        )
        let store = InMemoryReceiptStore()
        await store.save(originalReceipt)
        let coordinator = MuteCoordinator(audioController: audio, receiptStore: store)
        await coordinator.start()
        await audio.setStaleMuteFailures(uid: "built-in", count: 1)

        await coordinator.toggle()

        let receipt = await store.receipt(deviceUID: "built-in")
        XCTAssertEqual(receipt, originalReceipt)
    }

    func testMuteExpandsRestorableReceiptWhenTopologyAddsControls() async {
        let mute = AudioControl(kind: .mute, element: kAudioObjectPropertyElementMain)
        let volume = AudioControl(kind: .volume, element: kAudioObjectPropertyElementMain)
        let channelVolume = AudioControl(kind: .volume, element: 1)
        let audio = MultiDeviceAudioController(
            states: ["built-in": .live],
            defaultUID: "built-in",
            names: ["built-in": "Built-in"],
            expandedTopologyUIDs: ["built-in"]
        )
        let store = InMemoryReceiptStore()
        await store.save(
            AudioMutationReceipt(
                deviceUID: "built-in",
                originalValues: [
                    AudioControlValue(control: mute, value: 0),
                    AudioControlValue(control: volume, value: 0.7),
                ]
            )
        )
        let coordinator = MuteCoordinator(audioController: audio, receiptStore: store)
        await coordinator.start()

        await coordinator.toggle()

        let expandedReceipt = await store.receipt(deviceUID: "built-in")
        XCTAssertEqual(
            expandedReceipt?.originalValues,
            [
                AudioControlValue(control: mute, value: 0),
                AudioControlValue(control: volume, value: 0.7),
                AudioControlValue(control: channelVolume, value: 0.4),
            ]
        )
        let mutedState = await audio.state(uid: "built-in")
        XCTAssertEqual(mutedState, .muted)
        XCTAssertTrue(coordinator.restorationWarnings.isEmpty)

        await coordinator.toggle()

        let restoredState = await audio.state(uid: "built-in")
        let removedReceipt = await store.receipt(deviceUID: "built-in")
        XCTAssertEqual(restoredState, .live)
        XCTAssertNil(removedReceipt)
    }

    func testDuplicateDeviceUIDsDoNotCrashDeferredRestoration() async {
        let audio = MultiDeviceAudioController(
            states: ["built-in": .live],
            defaultUID: "built-in",
            duplicateUIDs: ["built-in"]
        )
        let coordinator = MuteCoordinator(
            audioController: audio,
            receiptStore: InMemoryReceiptStore()
        )
        await coordinator.start()
        await coordinator.selectTarget(.allInputs)
        await coordinator.toggle()

        await coordinator.toggle()

        XCTAssertEqual(coordinator.status, .live(deviceName: "All Inputs"))
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () async -> Bool
    ) async {
        for _ in 0..<200 {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Condition was not satisfied")
    }
}

private actor FakeAudioController: AudioDeviceControlling {
    static let uid = "test-device"
    static let muteControl = AudioControl(kind: .mute, element: kAudioObjectPropertyElementMain)
    static let volumeControl = AudioControl(kind: .volume, element: kAudioObjectPropertyElementMain)
    static let originalReceipt = AudioMutationReceipt(
        deviceUID: uid,
        originalValues: [
            AudioControlValue(control: muteControl, value: 0),
            AudioControlValue(control: volumeControl, value: 0.7),
        ]
    )

    private var state: AudioDeviceMuteState
    private let hasDefaultInput: Bool
    private var muteCalls = 0
    private var unmuteCalls = 0
    private var snapshotCalls = 0
    private var eventContinuation: AsyncStream<AudioHardwareEvent>.Continuation?
    private var remainingSuspendedUnmutes: Int
    private let restoresIncorrectly: Bool
    private var unmuteContinuation: CheckedContinuation<Void, Never>?
    private var shouldSuspendNextSnapshot = false
    private var snapshotContinuation: CheckedContinuation<Void, Never>?
    private var shouldSuspendNextEventsSetup = false
    private var eventsSetupContinuation: CheckedContinuation<Void, Never>?

    init(
        state: AudioDeviceMuteState,
        hasDefaultInput: Bool = true,
        suspendsUnmute: Bool = false,
        restoresIncorrectly: Bool = false
    ) {
        self.state = state
        self.hasDefaultInput = hasDefaultInput
        self.remainingSuspendedUnmutes = suspendsUnmute ? 1 : 0
        self.restoresIncorrectly = restoresIncorrectly
    }

    func inputDevices() -> [AudioDeviceDescriptor] {
        hasDefaultInput ? [Self.descriptor] : []
    }

    func defaultInputDevice() -> AudioDeviceDescriptor? {
        hasDefaultInput ? Self.descriptor : nil
    }

    func snapshot(deviceUID: String) async throws -> AudioDeviceSnapshot {
        snapshotCalls += 1
        if shouldSuspendNextSnapshot {
            shouldSuspendNextSnapshot = false
            await withCheckedContinuation { continuation in
                snapshotContinuation = continuation
            }
        }
        let values: [AudioControlValue] = switch state {
        case .live:
            [
                AudioControlValue(control: Self.muteControl, value: 0),
                AudioControlValue(control: Self.volumeControl, value: 0.7),
            ]
        case .muted:
            [
                AudioControlValue(control: Self.muteControl, value: 1),
                AudioControlValue(control: Self.volumeControl, value: 0),
            ]
        case .mixed:
            [
                AudioControlValue(control: Self.muteControl, value: 0),
                AudioControlValue(control: Self.volumeControl, value: 0.6),
                AudioControlValue(control: AudioControl(kind: .volume, element: 1), value: 0.7),
                AudioControlValue(control: AudioControl(kind: .volume, element: 2), value: 0),
            ]
        case .unsupported:
            []
        }
        return AudioDeviceSnapshot(device: Self.descriptor, values: values)
    }

    func mute(
        deviceUID: String,
        preserving receipt: AudioMutationReceipt?
    ) -> AudioMutationReceipt {
        muteCalls += 1
        state = .muted
        return receipt ?? Self.originalReceipt
    }

    func mute(
        deviceUID: String,
        preserving receipt: AudioMutationReceipt?,
        expected snapshot: AudioDeviceSnapshot
    ) throws -> AudioMutationReceipt {
        guard snapshot.device.uid == deviceUID,
              snapshot.muteState == state else {
            throw CoreAudioError.staleSnapshot(uid: deviceUID)
        }
        return mute(deviceUID: deviceUID, preserving: receipt)
    }

    func unmute(
        deviceUID: String,
        restoring receipt: AudioMutationReceipt?
    ) async {
        unmuteCalls += 1
        if remainingSuspendedUnmutes > 0 {
            remainingSuspendedUnmutes -= 1
            await withCheckedContinuation { continuation in
                unmuteContinuation = continuation
            }
        }
        state = restoresIncorrectly ? .mixed : .live
    }

    func events() async -> AsyncStream<AudioHardwareEvent> {
        if shouldSuspendNextEventsSetup {
            shouldSuspendNextEventsSetup = false
            await withCheckedContinuation { continuation in
                eventsSetupContinuation = continuation
            }
        }
        let (stream, continuation) = AsyncStream<AudioHardwareEvent>.makeStream()
        eventContinuation = continuation
        return stream
    }

    func muteCallCount() -> Int { muteCalls }
    func unmuteCallCount() -> Int { unmuteCalls }
    func snapshotCallCount() -> Int { snapshotCalls }

    func suspendNextSnapshot() {
        shouldSuspendNextSnapshot = true
    }

    func isSnapshotSuspended() -> Bool {
        snapshotContinuation != nil
    }

    func resumeSnapshot() {
        snapshotContinuation?.resume()
        snapshotContinuation = nil
    }

    func suspendNextEventsSetup() {
        shouldSuspendNextEventsSetup = true
    }

    func isEventsSetupSuspended() -> Bool {
        eventsSetupContinuation != nil
    }

    func resumeEventsSetup() {
        eventsSetupContinuation?.resume()
        eventsSetupContinuation = nil
    }

    func resumeUnmute() {
        unmuteContinuation?.resume()
        unmuteContinuation = nil
    }

    func simulateExternalState(_ state: AudioDeviceMuteState) {
        self.state = state
        eventContinuation?.yield(
            AudioHardwareEvent(
                kind: .controlValueChanged,
                objectID: Self.descriptor.objectID,
                selector: kAudioDevicePropertyMute,
                element: kAudioObjectPropertyElementMain
            )
        )
    }

    func simulateControlEvents(
        count: Int,
        objectID: AudioObjectID? = nil
    ) {
        let objectID = objectID ?? Self.descriptor.objectID
        for _ in 0..<count {
            eventContinuation?.yield(
                AudioHardwareEvent(
                    kind: .controlValueChanged,
                    objectID: objectID,
                    selector: kAudioDevicePropertyMute,
                    element: kAudioObjectPropertyElementMain
                )
            )
        }
    }

    func setStateWithoutEvent(_ state: AudioDeviceMuteState) {
        self.state = state
    }

    private static let descriptor = AudioDeviceDescriptor(
        objectID: 42,
        uid: uid,
        name: "Test Input",
        inputChannelCount: 2,
        isDefaultInput: true,
        capabilities: AudioDeviceCapabilities(
            nativeMuteControls: [muteControl],
            volumeControls: [volumeControl]
        )
    )
}

private actor CompletionFlag {
    private(set) var isCompleted = false

    func markCompleted() {
        isCompleted = true
    }
}

actor OperationRecorder {
    private var operations: [String] = []

    func record(_ operation: String) {
        operations.append(operation)
    }

    func reset() {
        operations.removeAll()
    }

    func values() -> [String] {
        operations
    }
}

actor InMemoryReceiptStore: AudioMutationReceiptStoring {
    private var receipts: [String: AudioMutationReceipt] = [:]
    private let operationRecorder: OperationRecorder?

    init(operationRecorder: OperationRecorder? = nil) {
        self.operationRecorder = operationRecorder
    }

    func receipt(deviceUID: String) -> AudioMutationReceipt? {
        receipts[deviceUID]
    }

    func save(_ receipt: AudioMutationReceipt) async {
        await operationRecorder?.record("receipt.save:\(receipt.deviceUID)")
        receipts[receipt.deviceUID] = receipt
    }

    func removeReceipt(deviceUID: String) async {
        await operationRecorder?.record("receipt.remove:\(deviceUID)")
        receipts.removeValue(forKey: deviceUID)
    }
}

private enum ReceiptStoreTestError: Error {
    case saveFailed
    case removalFailed
}

private actor FaultInjectingReceiptStore: AudioMutationReceiptStoring {
    private var receipts: [String: AudioMutationReceipt] = [:]
    private let failsSave: Bool
    private let failsRemoval: Bool

    init(failsSave: Bool = false, failsRemoval: Bool = false) {
        self.failsSave = failsSave
        self.failsRemoval = failsRemoval
    }

    func receipt(deviceUID: String) -> AudioMutationReceipt? {
        receipts[deviceUID]
    }

    func save(_ receipt: AudioMutationReceipt) throws {
        guard !failsSave else { throw ReceiptStoreTestError.saveFailed }
        receipts[receipt.deviceUID] = receipt
    }

    func removeReceipt(deviceUID: String) throws {
        guard !failsRemoval else { throw ReceiptStoreTestError.removalFailed }
        receipts.removeValue(forKey: deviceUID)
    }
}

private enum MultiDeviceAudioError: Error {
    case missingDevice(String)
    case unsupportedDevice(String)
}

actor MultiDeviceAudioController: AudioDeviceControlling {
    private static let muteControl = AudioControl(
        kind: .mute,
        element: kAudioObjectPropertyElementMain
    )
    private static let volumeControl = AudioControl(
        kind: .volume,
        element: kAudioObjectPropertyElementMain
    )
    private static let channelVolumeControl = AudioControl(kind: .volume, element: 1)

    private var states: [String: AudioDeviceMuteState]
    private var defaultUID: String
    private var names: [String: String]
    private let volumeOnlyUIDs: Set<String>
    private var eventContinuation: AsyncStream<AudioHardwareEvent>.Continuation?
    private var muteCalls: Set<String> = []
    private var muteAttempts: [String: Int] = [:]
    private var remainingMuteFailures: [String: Int] = [:]
    private var remainingUnmuteFailures: [String: Int] = [:]
    private var remainingStaleMuteFailures: [String: Int] = [:]
    private var restorationTopologyChangedUIDs: Set<String> = []
    private let duplicateUIDs: Set<String>
    private let expandedTopologyUIDs: Set<String>
    private var shouldSuspendNextInputDevices = false
    private var inputDevicesContinuation: CheckedContinuation<Void, Never>?
    private var muteUIDToSuspend: String?
    private var muteContinuation: CheckedContinuation<Void, Never>?
    private var unmuteUIDToSuspend: String?
    private var unmuteContinuation: CheckedContinuation<Void, Never>?
    private var remainingTransientUnsupportedInventories = 0
    private let operationRecorder: OperationRecorder?

    init(
        states: [String: AudioDeviceMuteState],
        defaultUID: String,
        names: [String: String] = [:],
        volumeOnlyUIDs: Set<String> = [],
        duplicateUIDs: Set<String> = [],
        expandedTopologyUIDs: Set<String> = [],
        operationRecorder: OperationRecorder? = nil
    ) {
        self.states = states
        self.defaultUID = defaultUID
        self.names = names
        self.volumeOnlyUIDs = volumeOnlyUIDs
        self.duplicateUIDs = duplicateUIDs
        self.expandedTopologyUIDs = expandedTopologyUIDs
        self.operationRecorder = operationRecorder
    }

    func inputDevices() async -> [AudioDeviceDescriptor] {
        if shouldSuspendNextInputDevices {
            shouldSuspendNextInputDevices = false
            await withCheckedContinuation { continuation in
                inputDevicesContinuation = continuation
            }
        }
        let forceUnsupported = remainingTransientUnsupportedInventories > 0
        if forceUnsupported {
            remainingTransientUnsupportedInventories -= 1
        }
        let devices = states.keys.sorted().compactMap {
            descriptor(uid: $0, forceUnsupported: forceUnsupported)
        }
        let duplicates = duplicateUIDs.compactMap { descriptor(uid: $0) }
        return devices + duplicates
    }

    func defaultInputDevice() -> AudioDeviceDescriptor? {
        descriptor(uid: defaultUID)
    }

    func snapshot(deviceUID: String) throws -> AudioDeviceSnapshot {
        guard let state = states[deviceUID], let device = descriptor(uid: deviceUID) else {
            throw MultiDeviceAudioError.missingDevice(deviceUID)
        }
        var values: [AudioControlValue] = switch state {
        case .live:
            [
                AudioControlValue(control: Self.muteControl, value: 0),
                AudioControlValue(control: Self.volumeControl, value: 0.7),
            ]
        case .muted:
            [
                AudioControlValue(control: Self.muteControl, value: 1),
                AudioControlValue(control: Self.volumeControl, value: 0),
            ]
        case .mixed:
            [
                AudioControlValue(control: Self.muteControl, value: 0),
                AudioControlValue(control: Self.volumeControl, value: 0),
                AudioControlValue(
                    control: AudioControl(kind: .volume, element: 1),
                    value: 0.7
                ),
            ]
        case .unsupported:
            []
        }
        if expandedTopologyUIDs.contains(deviceUID), state != .unsupported {
            values.append(
                AudioControlValue(
                    control: Self.channelVolumeControl,
                    value: state == .muted ? 0 : 0.4
                )
            )
        }
        return AudioDeviceSnapshot(device: device, values: values)
    }

    func mute(
        deviceUID: String,
        preserving receipt: AudioMutationReceipt?
    ) async throws -> AudioMutationReceipt {
        muteAttempts[deviceUID, default: 0] += 1
        if remainingMuteFailures[deviceUID, default: 0] > 0 {
            remainingMuteFailures[deviceUID, default: 0] -= 1
            throw MultiDeviceAudioError.missingDevice(deviceUID)
        }
        guard let state = states[deviceUID] else {
            throw MultiDeviceAudioError.missingDevice(deviceUID)
        }
        guard state != .unsupported else {
            throw MultiDeviceAudioError.unsupportedDevice(deviceUID)
        }
        if expandedTopologyUIDs.contains(deviceUID), let receipt {
            let current = try snapshot(deviceUID: deviceUID)
            guard receipt.hasSameControls(as: current.values) else {
                throw CoreAudioError.restorationTopologyChanged(uid: deviceUID)
            }
        }
        muteCalls.insert(deviceUID)
        states[deviceUID] = .muted
        await operationRecorder?.record("audio.mute:\(deviceUID)")
        return receipt ?? AudioMutationReceipt(
            deviceUID: deviceUID,
            originalValues: [
                AudioControlValue(control: Self.muteControl, value: state == .muted ? 1 : 0),
                AudioControlValue(control: Self.volumeControl, value: state == .muted ? 0 : 0.7),
            ]
        )
    }

    func mute(
        deviceUID: String,
        preserving receipt: AudioMutationReceipt?,
        expected snapshot: AudioDeviceSnapshot
    ) async throws -> AudioMutationReceipt {
        if muteUIDToSuspend == deviceUID {
            muteUIDToSuspend = nil
            await withCheckedContinuation { continuation in
                muteContinuation = continuation
            }
        }
        if remainingStaleMuteFailures[deviceUID, default: 0] > 0 {
            remainingStaleMuteFailures[deviceUID, default: 0] -= 1
            throw CoreAudioError.staleSnapshot(uid: deviceUID)
        }
        guard snapshot.device.uid == deviceUID,
              snapshot.muteState == states[deviceUID] else {
            throw CoreAudioError.staleSnapshot(uid: deviceUID)
        }
        return try await mute(deviceUID: deviceUID, preserving: receipt)
    }

    func unmute(
        deviceUID: String,
        restoring receipt: AudioMutationReceipt?
    ) async throws {
        if unmuteUIDToSuspend == deviceUID {
            unmuteUIDToSuspend = nil
            await withCheckedContinuation { continuation in
                unmuteContinuation = continuation
            }
        }
        if remainingUnmuteFailures[deviceUID, default: 0] > 0 {
            remainingUnmuteFailures[deviceUID, default: 0] -= 1
            throw MultiDeviceAudioError.missingDevice(deviceUID)
        }
        if restorationTopologyChangedUIDs.contains(deviceUID), receipt != nil {
            throw CoreAudioError.restorationTopologyChanged(uid: deviceUID)
        }
        guard let state = states[deviceUID] else {
            throw MultiDeviceAudioError.missingDevice(deviceUID)
        }
        guard state != .unsupported else {
            throw MultiDeviceAudioError.unsupportedDevice(deviceUID)
        }
        states[deviceUID] = .live
        await operationRecorder?.record("audio.unmute:\(deviceUID)")
    }

    func events() -> AsyncStream<AudioHardwareEvent> {
        let (stream, continuation) = AsyncStream<AudioHardwareEvent>.makeStream()
        eventContinuation = continuation
        return stream
    }

    func disconnect(uid: String) {
        states.removeValue(forKey: uid)
        emitDeviceListChange()
    }

    func connect(uid: String, state: AudioDeviceMuteState) {
        states[uid] = state
        emitDeviceListChange()
    }

    func state(uid: String) -> AudioDeviceMuteState? {
        states[uid]
    }

    func mutedUIDs() -> Set<String> {
        muteCalls
    }

    func muteAttemptCount(uid: String) -> Int {
        muteAttempts[uid, default: 0]
    }

    func setMuteFailures(uid: String, count: Int) {
        remainingMuteFailures[uid] = count
    }

    func setUnmuteFailures(uid: String, count: Int) {
        remainingUnmuteFailures[uid] = count
    }

    func setStaleMuteFailures(uid: String, count: Int) {
        remainingStaleMuteFailures[uid] = count
    }

    func suspendNextMute(uid: String) {
        muteUIDToSuspend = uid
    }

    func isMuteSuspended() -> Bool {
        muteContinuation != nil
    }

    func resumeMute() {
        muteContinuation?.resume()
        muteContinuation = nil
    }

    func suspendNextUnmute(uid: String) {
        unmuteUIDToSuspend = uid
    }

    func isUnmuteSuspended() -> Bool {
        unmuteContinuation != nil
    }

    func resumeUnmute() {
        unmuteContinuation?.resume()
        unmuteContinuation = nil
    }

    func setTransientUnsupportedInventories(_ count: Int) {
        remainingTransientUnsupportedInventories = count
    }

    func setRestorationTopologyChanged(uid: String, changed: Bool) {
        if changed {
            restorationTopologyChangedUIDs.insert(uid)
        } else {
            restorationTopologyChangedUIDs.remove(uid)
        }
    }

    func suspendNextInputDevices() {
        shouldSuspendNextInputDevices = true
    }

    func isInputDevicesSuspended() -> Bool {
        inputDevicesContinuation != nil
    }

    func resumeInputDevices() {
        inputDevicesContinuation?.resume()
        inputDevicesContinuation = nil
    }

    func changeDefault(to uid: String) {
        defaultUID = uid
        eventContinuation?.yield(
            AudioHardwareEvent(
                kind: .defaultInputChanged,
                objectID: AudioObjectID(kAudioObjectSystemObject),
                selector: kAudioHardwarePropertyDefaultInputDevice,
                element: kAudioObjectPropertyElementMain
            )
        )
    }

    func simulateExternalState(uid: String, state: AudioDeviceMuteState) {
        states[uid] = state
        guard let descriptor = descriptor(uid: uid) else { return }
        eventContinuation?.yield(
            AudioHardwareEvent(
                kind: .controlValueChanged,
                objectID: descriptor.objectID,
                deviceUID: uid,
                selector: kAudioDevicePropertyMute,
                element: kAudioObjectPropertyElementMain
            )
        )
    }

    func setStateWithoutEvent(uid: String, state: AudioDeviceMuteState) {
        states[uid] = state
    }

    private func descriptor(
        uid: String,
        forceUnsupported: Bool = false
    ) -> AudioDeviceDescriptor? {
        guard let state = states[uid] else { return nil }
        let controls: AudioDeviceCapabilities
        if state == .unsupported || forceUnsupported {
            controls = AudioDeviceCapabilities(nativeMuteControls: [], volumeControls: [])
        } else if volumeOnlyUIDs.contains(uid) {
            controls = AudioDeviceCapabilities(
                nativeMuteControls: [],
                volumeControls: [Self.volumeControl]
                    + (expandedTopologyUIDs.contains(uid) ? [Self.channelVolumeControl] : [])
            )
        } else {
            controls = AudioDeviceCapabilities(
                nativeMuteControls: [Self.muteControl],
                volumeControls: [Self.volumeControl]
                    + (expandedTopologyUIDs.contains(uid) ? [Self.channelVolumeControl] : [])
            )
        }
        return AudioDeviceDescriptor(
            objectID: AudioObjectID(abs(uid.hashValue % 10_000) + 1),
            uid: uid,
            name: names[uid] ?? uid,
            inputChannelCount: 2,
            isDefaultInput: uid == defaultUID,
            capabilities: controls
        )
    }

    private func emitDeviceListChange() {
        eventContinuation?.yield(
            AudioHardwareEvent(
                kind: .deviceListChanged,
                objectID: AudioObjectID(kAudioObjectSystemObject),
                selector: kAudioHardwarePropertyDevices,
                element: kAudioObjectPropertyElementMain
            )
        )
    }
}

private actor DurationRecorder {
    private var recorded: [Duration] = []

    func record(_ duration: Duration) {
        recorded.append(duration)
    }

    func values() -> [Duration] {
        recorded
    }
}
