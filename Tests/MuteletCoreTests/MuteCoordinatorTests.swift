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

    init(state: AudioDeviceMuteState, hasDefaultInput: Bool = true) {
        self.state = state
        self.hasDefaultInput = hasDefaultInput
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
    ) {
        unmuteCalls += 1
        state = .live
    }

    func events() -> AsyncStream<AudioHardwareEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func muteCallCount() -> Int { muteCalls }
    func unmuteCallCount() -> Int { unmuteCalls }

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
