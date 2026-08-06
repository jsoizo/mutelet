import Foundation

public enum MuteMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case toggle
    case pushToTalk

    public var id: Self { self }

    public var title: String {
        switch self {
        case .toggle:
            NSLocalizedString("Toggle", comment: "Toggle mute mode")
        case .pushToTalk:
            NSLocalizedString("Push to Talk", comment: "Push-to-talk mode")
        }
    }
}

public enum AudioTargetSelection: Codable, Hashable, Identifiable, Sendable {
    case systemDefault
    case device(uid: String, name: String)
    case allInputs

    public var id: String {
        switch self {
        case .systemDefault:
            "system-default"
        case let .device(uid, _):
            "device:\(uid)"
        case .allInputs:
            "all-inputs"
        }
    }

    public var title: String {
        switch self {
        case .systemDefault:
            NSLocalizedString("System Default", comment: "Default audio input")
        case let .device(_, name):
            name
        case .allInputs:
            NSLocalizedString("All Inputs", comment: "Every audio input")
        }
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public enum MuteStatus: Equatable, Sendable {
    case loading
    case live(deviceName: String)
    case muted(deviceName: String)
    case mixed(deviceName: String)
    case unavailable
    case disconnected(deviceName: String)
    case unsupported(deviceName: String)
    case partial(deviceName: String, muted: Int, live: Int, mixed: Int, unsupported: Int, failed: Int)
    case error(message: String)

    public var isMuted: Bool {
        if case .muted = self { return true }
        return false
    }

    public var canToggle: Bool {
        switch self {
        case .live, .muted, .mixed:
            true
        case let .partial(_, muted, live, mixed, _, _):
            muted + live + mixed > 0
        case .loading, .unavailable, .disconnected, .unsupported, .error:
            false
        }
    }

    public var title: String {
        switch self {
        case .loading:
            NSLocalizedString("Checking microphone…", comment: "Loading audio state")
        case let .live(deviceName):
            String(
                format: NSLocalizedString("Microphone on — %@", comment: "Live microphone status"),
                deviceName
            )
        case let .muted(deviceName):
            String(
                format: NSLocalizedString("Microphone muted — %@", comment: "Muted microphone status"),
                deviceName
            )
        case let .mixed(deviceName):
            String(
                format: NSLocalizedString("Microphone state mixed — %@", comment: "Mixed microphone status"),
                deviceName
            )
        case .unavailable:
            NSLocalizedString("No input device", comment: "No audio input")
        case let .disconnected(deviceName):
            String(
                format: NSLocalizedString("Input disconnected — %@", comment: "Disconnected input"),
                deviceName
            )
        case let .unsupported(deviceName):
            String(
                format: NSLocalizedString("Unsupported input — %@", comment: "Unsupported input"),
                deviceName
            )
        case let .partial(deviceName, muted, live, mixed, unsupported, failed):
            String(
                format: NSLocalizedString(
                    "Partial — %@ (%d muted, %d live, %d mixed, %d unsupported, %d failed)",
                    comment: "Partial multi-input status"
                ),
                deviceName,
                muted,
                live,
                mixed,
                unsupported,
                failed
            )
        case let .error(message):
            String(
                format: NSLocalizedString("Error — %@", comment: "Error status"),
                message
            )
        }
    }

    public var systemImageName: String {
        switch self {
        case .live:
            "mic.fill"
        case .muted:
            "mic.slash.fill"
        case .loading:
            "mic"
        case .unavailable, .disconnected, .unsupported:
            "mic.slash"
        case .mixed, .partial, .error:
            "exclamationmark.triangle.fill"
        }
    }
}
