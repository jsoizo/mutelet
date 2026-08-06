import Foundation

public struct MuteletPreferences: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var mode: MuteMode
    public var target: AudioTargetSelection
    public var hotKey: GlobalHotKeyConfiguration
    public var showsHUD: Bool

    public init(
        schemaVersion: Int = currentSchemaVersion,
        mode: MuteMode = .toggle,
        target: AudioTargetSelection = .systemDefault,
        hotKey: GlobalHotKeyConfiguration = .default,
        showsHUD: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.mode = mode
        self.target = target
        self.hotKey = hotKey
        self.showsHUD = showsHUD
    }
}

public protocol MuteletPreferencesStoring: Sendable {
    func load() async -> MuteletPreferences
    func save(_ preferences: MuteletPreferences) async throws
}

public actor UserDefaultsMuteletPreferencesStore: MuteletPreferencesStoring {
    private static let storageKey = "muteletPreferences.v1"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(suiteName: String? = nil) {
        if let suiteName, let defaults = UserDefaults(suiteName: suiteName) {
            self.defaults = defaults
        } else {
            self.defaults = .standard
        }
    }

    public func load() -> MuteletPreferences {
        guard let data = defaults.data(forKey: Self.storageKey),
              var preferences = try? decoder.decode(MuteletPreferences.self, from: data),
              preferences.schemaVersion == MuteletPreferences.currentSchemaVersion else {
            return MuteletPreferences()
        }
        if !preferences.hotKey.isValid {
            preferences.hotKey = .default
        }
        return preferences
    }

    public func save(_ preferences: MuteletPreferences) throws {
        var current = preferences
        current.schemaVersion = MuteletPreferences.currentSchemaVersion
        defaults.set(try encoder.encode(current), forKey: Self.storageKey)
    }
}
