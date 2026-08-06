import Carbon
import CoreAudio
import AppKit
import Foundation
import MuteletCore

@main
struct MuteletProbe {
    static func main() async {
        do {
            try await run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static func run(arguments: [String]) async throws {
        let command = arguments.first ?? "list"
        switch command {
        case "list":
            try await listDevices()
        case "snapshot":
            try await printSnapshot(uid: arguments.dropFirst().first)
        case "watch":
            try await watchEvents()
        case "hotkey":
            try await watchHotKey()
        case "roundtrip":
            guard arguments.contains("--confirm-write") else {
                throw ProbeError.writeConfirmationRequired
            }
            try await roundTrip(uid: value(after: "--uid", in: arguments))
        case "help", "--help", "-h":
            printUsage()
        default:
            throw ProbeError.unknownCommand(command)
        }
    }

    private static func listDevices() async throws {
        let controller = CoreAudioDeviceController()
        let devices = try await controller.inputDevices()
        if devices.isEmpty {
            print("No connected input devices.")
            return
        }
        for device in devices {
            let marker = device.isDefaultInput ? "*" : " "
            let mute = describe(controls: device.capabilities.nativeMuteControls)
            let volume = describe(controls: device.capabilities.volumeControls)
            print("\(marker) \(device.name)")
            print("  uid: \(device.uid)")
            print("  channels: \(device.inputChannelCount)")
            print("  mute: \(mute)")
            print("  volume: \(volume)")
        }
    }

    private static func printSnapshot(uid: String?) async throws {
        let controller = CoreAudioDeviceController()
        let deviceUID: String
        if let uid {
            deviceUID = uid
        } else if let defaultDevice = try await controller.defaultInputDevice() {
            deviceUID = defaultDevice.uid
        } else {
            throw ProbeError.noDefaultInput
        }
        let snapshot = try await controller.snapshot(deviceUID: deviceUID)
        print("\(snapshot.device.name) [\(snapshot.device.uid)]")
        if snapshot.values.isEmpty {
            print("  unsupported")
        }
        for value in snapshot.values {
            print("  \(value.control.kind.rawValue)[\(elementName(value.control.element))]: \(value.value)")
        }
    }

    private static func watchEvents() async throws {
        let controller = CoreAudioDeviceController()
        let events = try await controller.events()
        print("Watching Core Audio changes. Press Control-C to stop.")
        for await event in events {
            print("\(event.kind.rawValue): object=\(event.objectID) selector=\(fourCC(event.selector)) element=\(event.element)")
            if event.kind == .deviceListChanged {
                _ = try? await controller.inputDevices()
            }
        }
    }

    private static func watchHotKey() async throws {
        let stream = try await MainActor.run {
            let application = NSApplication.shared
            application.setActivationPolicy(.accessory)
            application.finishLaunching()
            let monitor = CarbonHotKeyMonitor()
            // Keep the monitor alive for the lifetime of the process through this task-local closure.
            let stream = try monitor.register(
                keyCode: UInt32(kVK_ANSI_M),
                modifiers: [.control, .shift],
                exclusive: false
            )
            HotKeyLifetime.shared.monitor = monitor
            return stream
        }
        print("Watching Control-Option-M. Press Control-C to stop.")
        for await event in stream {
            print(event.rawValue)
        }
    }

    private static func roundTrip(uid: String?) async throws {
        let controller = CoreAudioDeviceController()
        let deviceUID: String
        if let uid {
            deviceUID = uid
        } else if let defaultDevice = try await controller.defaultInputDevice() {
            deviceUID = defaultDevice.uid
        } else {
            throw ProbeError.noDefaultInput
        }

        print("Muting \(deviceUID) for 500 ms, then restoring its exact control values.")
        let receipt = try await controller.mute(deviceUID: deviceUID, preserving: nil)
        do {
            try await Task.sleep(for: .milliseconds(500))
            try await controller.unmute(deviceUID: deviceUID, restoring: receipt)
        } catch {
            try? await controller.unmute(deviceUID: deviceUID, restoring: receipt)
            throw error
        }
        print("Restored \(receipt.originalValues.count) control values.")
    }

    private static func describe(controls: [AudioControl]) -> String {
        guard !controls.isEmpty else { return "none" }
        return controls.map { elementName($0.element) }.joined(separator: ", ")
    }

    private static func elementName(_ element: UInt32) -> String {
        element == kAudioObjectPropertyElementMain ? "main" : "channel \(element)"
    }

    private static func fourCC(_ value: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((value >> UInt32($0)) & 0xFF) }
        return String(bytes: bytes, encoding: .macOSRoman) ?? String(value)
    }

    private static func value(after option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func printUsage() {
        print(
            """
            Usage: mutelet-probe <command>

              list                         List input devices and writable controls (default)
              snapshot [uid]               Read control values for a device or the default input
              watch                        Watch Core Audio device and control change events
              hotkey                       Watch Control-Option-M pressed/released events
              roundtrip --confirm-write    Mute the default input for 500 ms and restore it
              roundtrip --uid UID --confirm-write
            """
        )
    }
}

private enum ProbeError: Error, CustomStringConvertible {
    case unknownCommand(String)
    case noDefaultInput
    case writeConfirmationRequired

    var description: String {
        switch self {
        case let .unknownCommand(command):
            return "Unknown command '\(command)'. Run with --help for usage."
        case .noDefaultInput:
            return "No default input device is available."
        case .writeConfirmationRequired:
            return "The roundtrip command changes real input controls; pass --confirm-write to continue."
        }
    }
}

@MainActor
private final class HotKeyLifetime {
    static let shared = HotKeyLifetime()
    var monitor: CarbonHotKeyMonitor?
}
