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
}
