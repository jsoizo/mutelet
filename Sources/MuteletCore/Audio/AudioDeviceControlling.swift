import Foundation

public protocol AudioDeviceControlling: Sendable {
    func inputDevices() async throws -> [AudioDeviceDescriptor]
    func defaultInputDevice() async throws -> AudioDeviceDescriptor?
    func snapshot(deviceUID: String) async throws -> AudioDeviceSnapshot
    func mute(
        deviceUID: String,
        preserving receipt: AudioMutationReceipt?
    ) async throws -> AudioMutationReceipt
    func mute(
        deviceUID: String,
        preserving receipt: AudioMutationReceipt?,
        expected snapshot: AudioDeviceSnapshot
    ) async throws -> AudioMutationReceipt
    func unmute(
        deviceUID: String,
        restoring receipt: AudioMutationReceipt?
    ) async throws
    func events() async throws -> AsyncStream<AudioHardwareEvent>
}

public extension AudioDeviceControlling {
    func mute(
        deviceUID: String,
        preserving receipt: AudioMutationReceipt?,
        expected snapshot: AudioDeviceSnapshot
    ) async throws -> AudioMutationReceipt {
        try await mute(deviceUID: deviceUID, preserving: receipt)
    }
}
