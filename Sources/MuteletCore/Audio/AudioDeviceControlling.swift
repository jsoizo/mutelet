import Foundation

public protocol AudioDeviceControlling: Sendable {
    func inputDevices() async throws -> [AudioDeviceDescriptor]
    func defaultInputDevice() async throws -> AudioDeviceDescriptor?
    func snapshot(deviceUID: String) async throws -> AudioDeviceSnapshot
    func mute(
        deviceUID: String,
        preserving receipt: AudioMutationReceipt?
    ) async throws -> AudioMutationReceipt
    func unmute(
        deviceUID: String,
        restoring receipt: AudioMutationReceipt?
    ) async throws
    func events() async throws -> AsyncStream<AudioHardwareEvent>
}
