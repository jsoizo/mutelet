import CoreAudio
import XCTest
@testable import MuteletCore

final class AudioDeviceModelsTests: XCTestCase {
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
