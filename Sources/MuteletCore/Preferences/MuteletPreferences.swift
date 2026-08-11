import Foundation

public struct MuteletPreferences: Equatable, Sendable {
    public var microphone: MicrophonePreferences
    public var shortcuts: ShortcutPreferences
    public var hud: HUDPreferences

    public init(
        microphone: MicrophonePreferences = MicrophonePreferences(),
        shortcuts: ShortcutPreferences = ShortcutPreferences(),
        hud: HUDPreferences = HUDPreferences()
    ) {
        self.microphone = microphone
        self.shortcuts = shortcuts
        self.hud = hud
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

public struct HUDPreferences: Equatable, Sendable {
    public var isEnabled: Bool

    public init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
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
    case migrationSaveFailed
}

public protocol MuteletPreferencesStoring: Sendable {
    func load() async -> PreferencesLoadResult
    func save(_ preferences: MuteletPreferences) async throws
}
