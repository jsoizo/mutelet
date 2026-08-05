import Foundation

public enum MuteMode: String, CaseIterable, Identifiable, Sendable {
    case toggle
    case pushToTalk

    public var id: Self { self }

    public var title: String {
        switch self {
        case .toggle:
            "Toggle"
        case .pushToTalk:
            "Push to Talk"
        }
    }
}

public enum AudioTargetSelection: Hashable, Identifiable, Sendable {
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
            "System Default"
        case let .device(_, name):
            name
        case .allInputs:
            "All Inputs"
        }
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
            "Checking microphone…"
        case let .live(deviceName):
            "Microphone on — \(deviceName)"
        case let .muted(deviceName):
            "Microphone muted — \(deviceName)"
        case let .mixed(deviceName):
            "Microphone state mixed — \(deviceName)"
        case .unavailable:
            "No input device"
        case let .disconnected(deviceName):
            "Input disconnected — \(deviceName)"
        case let .unsupported(deviceName):
            "Unsupported input — \(deviceName)"
        case let .partial(deviceName, muted, live, mixed, unsupported, failed):
            "Partial — \(deviceName) (\(muted) muted, \(live) live, \(mixed) mixed, \(unsupported) unsupported, \(failed) failed)"
        case let .error(message):
            "Error — \(message)"
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
        case .mixed, .unavailable, .disconnected, .unsupported, .partial, .error:
            "exclamationmark.triangle.fill"
        }
    }
}
