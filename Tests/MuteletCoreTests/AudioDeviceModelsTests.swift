import CoreAudio
import XCTest
@testable import MuteletCore

final class AudioDeviceModelsTests: XCTestCase {
    func testIncompleteChannelCoverageIsUnsupported() {
        let partialCapabilities = AudioDeviceCapabilities(
            nativeMuteControls: [],
            volumeControls: [AudioControl(kind: .volume, element: 1)],
            coversAllInputChannels: false
        )
        let device = AudioDeviceDescriptor(
            objectID: 99,
            uid: "partial",
            name: "Partial Input",
            inputChannelCount: 2,
            isDefaultInput: true,
            capabilities: partialCapabilities
        )
        let snapshot = AudioDeviceSnapshot(
            device: device,
            values: [
                AudioControlValue(
                    control: AudioControl(kind: .volume, element: 1),
                    value: 0
                ),
            ]
        )

        XCTAssertFalse(partialCapabilities.isSupported)
        XCTAssertEqual(snapshot.muteState, .unsupported)
    }

    func testUnsupportedWhenNoWritableControlsExist() {
        let capabilities = AudioDeviceCapabilities(
            nativeMuteControls: [],
            volumeControls: []
        )

        XCTAssertFalse(capabilities.isSupported)
        XCTAssertFalse(capabilities.usesVolumeFallbackOnly)
    }

    func testNativeMuteIsPreferredSupport() {
        let capabilities = AudioDeviceCapabilities(
            nativeMuteControls: [AudioControl(kind: .mute, element: kAudioObjectPropertyElementMain)],
            volumeControls: []
        )

        XCTAssertTrue(capabilities.isSupported)
        XCTAssertFalse(capabilities.usesVolumeFallbackOnly)
    }

    func testVolumeOnlyDeviceIsMarkedAsFallback() {
        let capabilities = AudioDeviceCapabilities(
            nativeMuteControls: [],
            volumeControls: [AudioControl(kind: .volume, element: 1)]
        )

        XCTAssertTrue(capabilities.isSupported)
        XCTAssertTrue(capabilities.usesVolumeFallbackOnly)
    }

    func testMainElementClassification() {
        XCTAssertTrue(
            AudioControl(kind: .mute, element: kAudioObjectPropertyElementMain).isMain
        )
        XCTAssertFalse(AudioControl(kind: .volume, element: 1).isMain)
    }

    func testSnapshotTreatsNativeMuteAsMuted() {
        let snapshot = makeSnapshot(muteValues: [1], volumeValues: [0.7])
        XCTAssertEqual(snapshot.muteState, .muted)
    }

    func testSnapshotTreatsZeroVolumeAsMuted() {
        let snapshot = makeSnapshot(muteValues: [0], volumeValues: [0])
        XCTAssertEqual(snapshot.muteState, .muted)
    }

    func testSnapshotTreatsChannelDifferenceAsMixed() {
        let snapshot = makeSnapshot(muteValues: [], volumeValues: [0, 0.7])
        XCTAssertEqual(snapshot.muteState, .mixed)
    }

    func testSnapshotTreatsAudibleControlsAsLive() {
        let snapshot = makeSnapshot(muteValues: [0], volumeValues: [0.7])
        XCTAssertEqual(snapshot.muteState, .live)
    }

    func testSnapshotTreatsHeterogeneousPartiallySilentChannelsAsMixed() {
        XCTAssertEqual(
            makeHeterogeneousSnapshot(channelOneMute: 1, channelTwoVolume: 0.7).muteState,
            .mixed
        )
        XCTAssertEqual(
            makeHeterogeneousSnapshot(channelOneMute: 0, channelTwoVolume: 0).muteState,
            .mixed
        )
    }

    func testSnapshotTreatsHeterogeneousFullySilentChannelsAsMuted() {
        XCTAssertEqual(
            makeHeterogeneousSnapshot(channelOneMute: 1, channelTwoVolume: 0).muteState,
            .muted
        )
    }

    func testReceiptRequiresAnExactNonDuplicatedControlTopology() {
        let mute = AudioControl(kind: .mute, element: kAudioObjectPropertyElementMain)
        let volume = AudioControl(kind: .volume, element: kAudioObjectPropertyElementMain)
        let receipt = AudioMutationReceipt(
            deviceUID: "test-device",
            originalValues: [AudioControlValue(control: mute, value: 0)]
        )

        XCTAssertTrue(
            receipt.hasSameControls(as: [AudioControlValue(control: mute, value: 1)])
        )
        XCTAssertFalse(
            receipt.hasSameControls(as: [
                AudioControlValue(control: mute, value: 1),
                AudioControlValue(control: volume, value: 0),
            ])
        )
        XCTAssertFalse(
            receipt.hasSameControls(as: [
                AudioControlValue(control: mute, value: 1),
                AudioControlValue(control: mute, value: 1),
            ])
        )
    }

    func testReceiptCanRestoreWhenCurrentTopologyOnlyAddsControls() {
        let mute = AudioControl(kind: .mute, element: kAudioObjectPropertyElementMain)
        let volume = AudioControl(kind: .volume, element: kAudioObjectPropertyElementMain)
        let receipt = AudioMutationReceipt(
            deviceUID: "test-device",
            originalValues: [AudioControlValue(control: mute, value: 0)]
        )

        XCTAssertTrue(
            receipt.canRestore(from: [
                AudioControlValue(control: mute, value: 1),
                AudioControlValue(control: volume, value: 0.7),
            ])
        )
        XCTAssertFalse(
            receipt.canRestore(from: [
                AudioControlValue(control: volume, value: 0.7),
            ])
        )
    }

    func testReceiptIncludesOriginalValuesForNewControls() throws {
        let mute = AudioControl(kind: .mute, element: kAudioObjectPropertyElementMain)
        let volume = AudioControl(kind: .volume, element: kAudioObjectPropertyElementMain)
        let channelVolume = AudioControl(kind: .volume, element: 1)
        let receipt = AudioMutationReceipt(
            deviceUID: "test-device",
            originalValues: [
                AudioControlValue(control: mute, value: 0),
                AudioControlValue(control: volume, value: 0.7),
            ]
        )

        let expanded = try XCTUnwrap(
            receipt.includingNewControls(from: [
                AudioControlValue(control: mute, value: 1),
                AudioControlValue(control: volume, value: 0),
                AudioControlValue(control: channelVolume, value: 0.4),
            ])
        )

        XCTAssertEqual(
            expanded.originalValues,
            receipt.originalValues + [
                AudioControlValue(control: channelVolume, value: 0.4),
            ]
        )
    }

    func testLegacyAudioControllerUsesDefaultExpectedSnapshotImplementation() async throws {
        let controller = LegacyAudioController()
        let snapshot = await controller.snapshot(deviceUID: LegacyAudioController.uid)

        _ = try await controller.mute(
            deviceUID: LegacyAudioController.uid,
            preserving: nil,
            expected: snapshot
        )

        let muteCalls = await controller.muteCallCount()
        XCTAssertEqual(muteCalls, 1)
    }

    private func makeSnapshot(
        muteValues: [Float],
        volumeValues: [Float]
    ) -> AudioDeviceSnapshot {
        let muteControls = muteValues.indices.map {
            AudioControl(kind: .mute, element: UInt32($0 + 1))
        }
        let volumeControls = volumeValues.indices.map {
            AudioControl(kind: .volume, element: UInt32($0 + 1))
        }
        let descriptor = AudioDeviceDescriptor(
            objectID: 42,
            uid: "test-device",
            name: "Test Input",
            inputChannelCount: UInt32(max(muteValues.count, volumeValues.count)),
            isDefaultInput: true,
            capabilities: AudioDeviceCapabilities(
                nativeMuteControls: muteControls,
                volumeControls: volumeControls
            )
        )
        let values = zip(muteControls, muteValues).map(AudioControlValue.init)
            + zip(volumeControls, volumeValues).map(AudioControlValue.init)
        return AudioDeviceSnapshot(device: descriptor, values: values)
    }

    private func makeHeterogeneousSnapshot(
        channelOneMute: Float,
        channelTwoVolume: Float
    ) -> AudioDeviceSnapshot {
        let channelOne = AudioControl(kind: .mute, element: 1)
        let channelTwo = AudioControl(kind: .volume, element: 2)
        return AudioDeviceSnapshot(
            device: AudioDeviceDescriptor(
                objectID: 43,
                uid: "heterogeneous-device",
                name: "Heterogeneous Input",
                inputChannelCount: 2,
                isDefaultInput: true,
                capabilities: AudioDeviceCapabilities(
                    nativeMuteControls: [channelOne],
                    volumeControls: [channelTwo]
                )
            ),
            values: [
                AudioControlValue(control: channelOne, value: channelOneMute),
                AudioControlValue(control: channelTwo, value: channelTwoVolume),
            ]
        )
    }
}

private actor LegacyAudioController: AudioDeviceControlling {
    static let uid = "legacy-device"
    private static let control = AudioControl(
        kind: .mute,
        element: kAudioObjectPropertyElementMain
    )
    private static let device = AudioDeviceDescriptor(
        objectID: 44,
        uid: uid,
        name: "Legacy Input",
        inputChannelCount: 1,
        isDefaultInput: true,
        capabilities: AudioDeviceCapabilities(
            nativeMuteControls: [control],
            volumeControls: []
        )
    )

    private var muteCalls = 0

    func inputDevices() -> [AudioDeviceDescriptor] { [Self.device] }
    func defaultInputDevice() -> AudioDeviceDescriptor? { Self.device }

    func snapshot(deviceUID: String) -> AudioDeviceSnapshot {
        AudioDeviceSnapshot(
            device: Self.device,
            values: [AudioControlValue(control: Self.control, value: 0)]
        )
    }

    func mute(
        deviceUID: String,
        preserving receipt: AudioMutationReceipt?
    ) -> AudioMutationReceipt {
        muteCalls += 1
        return receipt ?? AudioMutationReceipt(
            deviceUID: deviceUID,
            originalValues: [AudioControlValue(control: Self.control, value: 0)]
        )
    }

    func unmute(
        deviceUID: String,
        restoring receipt: AudioMutationReceipt?
    ) {}

    func events() -> AsyncStream<AudioHardwareEvent> {
        AsyncStream { $0.finish() }
    }

    func muteCallCount() -> Int { muteCalls }
}
