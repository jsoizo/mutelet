import CoreAudio
import Foundation
import MuteletCore

actor UITestingAudioController: AudioDeviceControlling {
    private static let uid = "ui-testing-input"
    private static let muteControl = AudioControl(
        kind: .mute,
        element: kAudioObjectPropertyElementMain
    )
    private static let volumeControl = AudioControl(
        kind: .volume,
        element: kAudioObjectPropertyElementMain
    )

    private var state: AudioDeviceMuteState
    private let hasDevice: Bool

    init(arguments: [String]) {
        let value = arguments
            .first { $0.hasPrefix("--ui-state=") }?
            .split(separator: "=", maxSplits: 1)
            .last
            .flatMap { AudioDeviceMuteState(rawValue: String($0)) }
        state = value ?? .live
        hasDevice = !arguments.contains("--ui-no-input")
    }

    func inputDevices() -> [AudioDeviceDescriptor] {
        hasDevice ? [descriptor] : []
    }

    func defaultInputDevice() -> AudioDeviceDescriptor? {
        hasDevice ? descriptor : nil
    }

    func snapshot(deviceUID: String) throws -> AudioDeviceSnapshot {
        AudioDeviceSnapshot(device: descriptor, values: values)
    }

    func mute(
        deviceUID: String,
        preserving receipt: AudioMutationReceipt?
    ) -> AudioMutationReceipt {
        let originalValues = values
        state = .muted
        return receipt ?? AudioMutationReceipt(
            deviceUID: Self.uid,
            originalValues: originalValues
        )
    }

    func unmute(
        deviceUID: String,
        restoring receipt: AudioMutationReceipt?
    ) {
        state = .live
    }

    func events() -> AsyncStream<AudioHardwareEvent> {
        AsyncStream { _ in }
    }

    private var descriptor: AudioDeviceDescriptor {
        let capabilities = state == .unsupported
            ? AudioDeviceCapabilities(nativeMuteControls: [], volumeControls: [])
            : AudioDeviceCapabilities(
                nativeMuteControls: [Self.muteControl],
                volumeControls: [Self.volumeControl]
            )
        return AudioDeviceDescriptor(
            objectID: 9_001,
            uid: Self.uid,
            name: "UI Test Microphone",
            inputChannelCount: 2,
            isDefaultInput: true,
            capabilities: capabilities
        )
    }

    private var values: [AudioControlValue] {
        switch state {
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
    }
}

actor UITestingPreferencesStore: MuteletPreferencesStoring {
    private let preferences: MuteletPreferences

    init(arguments: [String]) {
        preferences = MuteletPreferences(
            mode: arguments.contains("--ui-push-to-talk") ? .pushToTalk : .toggle
        )
    }

    func load() -> MuteletPreferences {
        preferences
    }

    func save(_ preferences: MuteletPreferences) {}
}

actor UITestingReceiptStore: AudioMutationReceiptStoring {
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
