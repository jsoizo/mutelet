import Foundation

public enum MuteStatus: Equatable, Sendable {
    case loading
    case live(deviceName: String)
    case muted(deviceName: String)
    case mixed(deviceName: String)
    case unavailable
    case unsupported(deviceName: String)
    case error(message: String)

    public var isMuted: Bool {
        if case .muted = self { return true }
        return false
    }

    public var canToggle: Bool {
        switch self {
        case .live, .muted, .mixed:
            true
        case .loading, .unavailable, .unsupported, .error:
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
        case let .unsupported(deviceName):
            "Unsupported input — \(deviceName)"
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
        case .mixed, .unavailable, .unsupported, .error:
            "exclamationmark.triangle.fill"
        }
    }
}
