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
        for _ in 0..<100 where await audio.muteCallCount() < 2 {
            await Task.yield()
        }

        let muteCalls = await audio.muteCallCount()
        XCTAssertEqual(coordinator.status, .muted(deviceName: "Test Input"))
        XCTAssertEqual(muteCalls, 2)
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
    private var eventContinuation: AsyncStream<AudioHardwareEvent>.Continuation?
    private let suspendsUnmute: Bool
    private var unmuteContinuation: CheckedContinuation<Void, Never>?

    init(
        state: AudioDeviceMuteState,
        hasDefaultInput: Bool = true,
        suspendsUnmute: Bool = false
    ) {
        self.state = state
        self.hasDefaultInput = hasDefaultInput
        self.suspendsUnmute = suspendsUnmute
    }

    func inputDevices() -> [AudioDeviceDescriptor] {
        hasDefaultInput ? [Self.descriptor] : []
    }

    func defaultInputDevice() -> AudioDeviceDescriptor? {
        hasDefaultInput ? Self.descriptor : nil
    }

    func snapshot(deviceUID: String) throws -> AudioDeviceSnapshot {
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
                AudioControlValue(control: Self.volumeControl, value: 0),
                AudioControlValue(control: AudioControl(kind: .volume, element: 1), value: 0.7),
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

    func unmute(
        deviceUID: String,
        restoring receipt: AudioMutationReceipt?
    ) async {
        unmuteCalls += 1
        if suspendsUnmute {
            await withCheckedContinuation { continuation in
                unmuteContinuation = continuation
            }
        }
        state = .live
    }

    func events() -> AsyncStream<AudioHardwareEvent> {
        let (stream, continuation) = AsyncStream<AudioHardwareEvent>.makeStream()
        eventContinuation = continuation
        return stream
    }

    func muteCallCount() -> Int { muteCalls }
    func unmuteCallCount() -> Int { unmuteCalls }

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

private actor InMemoryReceiptStore: AudioMutationReceiptStoring {
    private var receipts: [String: AudioMutationReceipt] = [:]

    func receipt(deviceUID: String) -> AudioMutationReceipt? {
        receipts[deviceUID]
    }

    func save(_ receipt: AudioMutationReceipt) {
        receipts[receipt.deviceUID] = receipt
    }

    func removeReceipt(deviceUID: String) {
        receipts.removeValue(forKey: deviceUID)
    }
}
