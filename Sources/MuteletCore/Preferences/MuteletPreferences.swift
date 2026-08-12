import Foundation

public struct MuteletPreferences: Equatable, Sendable {
    public var microphone: MicrophonePreferences
    public var shortcuts: ShortcutPreferences
    public var hud: HUDPreferences
    public var statusOverlay: StatusOverlayPreferences

    public init(
        microphone: MicrophonePreferences = MicrophonePreferences(),
        shortcuts: ShortcutPreferences = ShortcutPreferences(),
        hud: HUDPreferences = HUDPreferences(),
        statusOverlay: StatusOverlayPreferences = StatusOverlayPreferences()
    ) {
        self.microphone = microphone
        self.shortcuts = shortcuts
        self.hud = hud
        self.statusOverlay = statusOverlay
    }
}

public struct MicrophonePreferences: Equatable, Sendable {
    public var mode: MuteMode
    public var target: AudioTargetSelection

    public init(
        mode: MuteMode = .toggle,
        target: AudioTargetSelection = .systemDefault
    ) {
        self.mode = mode
        self.target = target
    }
}

public struct ShortcutPreferences: Equatable, Sendable {
    public var primary: GlobalHotKeyConfiguration

    public init(primary: GlobalHotKeyConfiguration = .default) {
        self.primary = primary
    }
}

public enum HUDSize: String, Codable, CaseIterable, Hashable, Sendable {
    case compact
    case standard
    case large
}

public enum HUDHorizontalPosition: String, Codable, CaseIterable, Hashable, Sendable {
    case leading
    case center
    case trailing
}

public enum HUDVerticalPosition: String, Codable, CaseIterable, Hashable, Sendable {
    case top
    case center
    case bottom
}

public struct HUDPosition: Codable, Equatable, Hashable, Sendable {
    public var horizontal: HUDHorizontalPosition
    public var vertical: HUDVerticalPosition

    public init(
        horizontal: HUDHorizontalPosition = .center,
        vertical: HUDVerticalPosition = .center
    ) {
        self.horizontal = horizontal
        self.vertical = vertical
    }
}

public enum HUDDisplayTarget: String, Codable, CaseIterable, Hashable, Sendable {
    case pointer
    case main
    case all
}

public enum HUDDuration: String, Codable, CaseIterable, Hashable, Sendable {
    case short
    case standard
    case long
}

public struct HUDPreferences: Equatable, Sendable {
    public var isEnabled: Bool
    public var size: HUDSize
    public var position: HUDPosition
    public var displayTarget: HUDDisplayTarget
    public var duration: HUDDuration

    public init(
        isEnabled: Bool = true,
        size: HUDSize = .standard,
        position: HUDPosition = HUDPosition(),
        displayTarget: HUDDisplayTarget = .pointer,
        duration: HUDDuration = .standard
    ) {
        self.isEnabled = isEnabled
        self.size = size
        self.position = position
        self.displayTarget = displayTarget
        self.duration = duration
    }
}

public enum StatusOverlayVisibility: String, Codable, CaseIterable, Hashable, Sendable {
    case always
    case whenPotentiallyLive

    public func includes(_ status: MuteStatus) -> Bool {
        switch self {
        case .always:
            true
        case .whenPotentiallyLive:
            switch status {
            case .muted, .unavailable, .disconnected:
                false
            case .loading, .live, .mixed, .unsupported, .partial, .error:
                true
            }
        }
    }
}

public enum StatusOverlayContentStyle: String, Codable, CaseIterable, Hashable, Sendable {
    case iconOnly
    case iconAndStatus
}

public enum StatusOverlaySize: String, Codable, CaseIterable, Hashable, Sendable {
    case compact
    case standard
    case large
}

public enum StatusOverlayDisplayTarget: Codable, Equatable, Hashable, Sendable {
    case main
    case display(id: String, lastKnownName: String)
}

public struct NormalizedScreenPosition: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double = 1, y: Double = 0.5) {
        self.x = x
        self.y = y
    }
}

public struct StatusOverlayPreferences: Equatable, Sendable {
    public var isEnabled: Bool
    public var visibility: StatusOverlayVisibility
    public var contentStyle: StatusOverlayContentStyle
    public var size: StatusOverlaySize
    public var displayTarget: StatusOverlayDisplayTarget
    public var position: NormalizedScreenPosition
    public var togglesMuteOnClick: Bool

    public init(
        isEnabled: Bool = false,
        visibility: StatusOverlayVisibility = .always,
        contentStyle: StatusOverlayContentStyle = .iconOnly,
        size: StatusOverlaySize = .standard,
        displayTarget: StatusOverlayDisplayTarget = .main,
        position: NormalizedScreenPosition = NormalizedScreenPosition(),
        togglesMuteOnClick: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.visibility = visibility
        self.contentStyle = contentStyle
        self.size = size
        self.displayTarget = displayTarget
        self.position = position
        self.togglesMuteOnClick = togglesMuteOnClick
    }
}

public enum PreferencesLoadResult: Equatable, Sendable {
    case loaded(MuteletPreferences)
    case defaults
    case recovered(MuteletPreferences, issues: [PreferencesRecoveryIssue])
}

public enum PreferencesRecoveryIssue: Equatable, Sendable {
    case corruptedData
    case unsupportedSchemaVersion(Int)
    case invalidMicrophone
    case invalidShortcut
    case invalidHUD
    case invalidStatusOverlay
    case migrationSaveFailed
}

public protocol MuteletPreferencesStoring: Sendable {
    func load() async -> PreferencesLoadResult
    func save(_ preferences: MuteletPreferences) async throws
}
