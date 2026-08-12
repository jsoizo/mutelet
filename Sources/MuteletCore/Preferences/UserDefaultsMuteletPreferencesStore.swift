import Foundation

public actor UserDefaultsMuteletPreferencesStore: MuteletPreferencesStoring {
    private static let storageKey = "muteletPreferences"
    private static let currentSchemaVersion = 3

    private struct StoredPreferencesHeader: Decodable {
        let schemaVersion: Int
    }

    private struct StoredPreferencesV1: Codable {
        let schemaVersion: Int
        let microphone: StoredMicrophonePreferencesV1
        let shortcuts: StoredShortcutPreferencesV1
        let hud: StoredHUDPreferencesV1

        init(preferences: MuteletPreferences) {
            schemaVersion = 1
            microphone = StoredMicrophonePreferencesV1(preferences: preferences.microphone)
            shortcuts = StoredShortcutPreferencesV1(preferences: preferences.shortcuts)
            hud = StoredHUDPreferencesV1(preferences: preferences.hud)
        }

        func decodePreferences() -> DecodedPreferences {
            var preferences = MuteletPreferences()
            var issues: [PreferencesRecoveryIssue] = []

            if let microphonePreferences = microphone.decodePreferences() {
                preferences.microphone = microphonePreferences
            } else {
                issues.append(.invalidMicrophone)
            }

            if let shortcutPreferences = shortcuts.decodePreferences() {
                preferences.shortcuts = shortcutPreferences
            } else {
                issues.append(.invalidShortcut)
            }

            preferences.hud = hud.preferences
            return DecodedPreferences(
                preferences: preferences,
                issues: issues,
                requiresSave: true
            )
        }
    }

    private struct StoredPreferencesV2: Codable {
        let schemaVersion: Int
        let microphone: StoredMicrophonePreferencesV1
        let shortcuts: StoredShortcutPreferencesV1
        let hud: StoredHUDPreferencesV2

        init(preferences: MuteletPreferences) {
            schemaVersion = 2
            microphone = StoredMicrophonePreferencesV1(preferences: preferences.microphone)
            shortcuts = StoredShortcutPreferencesV1(preferences: preferences.shortcuts)
            hud = StoredHUDPreferencesV2(preferences: preferences.hud)
        }

        func decodePreferences() -> DecodedPreferences {
            var preferences = MuteletPreferences()
            var issues: [PreferencesRecoveryIssue] = []

            if let microphonePreferences = microphone.decodePreferences() {
                preferences.microphone = microphonePreferences
            } else {
                issues.append(.invalidMicrophone)
            }

            if let shortcutPreferences = shortcuts.decodePreferences() {
                preferences.shortcuts = shortcutPreferences
            } else {
                issues.append(.invalidShortcut)
            }

            if let hudPreferences = hud.decodePreferences() {
                preferences.hud = hudPreferences
            } else {
                issues.append(.invalidHUD)
            }

            return DecodedPreferences(
                preferences: preferences,
                issues: issues,
                requiresSave: true
            )
        }
    }

    private struct StoredPreferencesV3: Codable {
        let schemaVersion: Int
        let microphone: StoredMicrophonePreferencesV1
        let shortcuts: StoredShortcutPreferencesV1
        let hud: StoredHUDPreferencesV2
        let statusOverlay: StoredStatusOverlayPreferencesV3

        init(preferences: MuteletPreferences) {
            schemaVersion = UserDefaultsMuteletPreferencesStore.currentSchemaVersion
            microphone = StoredMicrophonePreferencesV1(preferences: preferences.microphone)
            shortcuts = StoredShortcutPreferencesV1(preferences: preferences.shortcuts)
            hud = StoredHUDPreferencesV2(preferences: preferences.hud)
            statusOverlay = StoredStatusOverlayPreferencesV3(
                preferences: preferences.statusOverlay
            )
        }

        func decodePreferences() -> DecodedPreferences {
            var preferences = MuteletPreferences()
            var issues: [PreferencesRecoveryIssue] = []

            if let microphonePreferences = microphone.decodePreferences() {
                preferences.microphone = microphonePreferences
            } else {
                issues.append(.invalidMicrophone)
            }

            if let shortcutPreferences = shortcuts.decodePreferences() {
                preferences.shortcuts = shortcutPreferences
            } else {
                issues.append(.invalidShortcut)
            }

            if let hudPreferences = hud.decodePreferences() {
                preferences.hud = hudPreferences
            } else {
                issues.append(.invalidHUD)
            }

            if let overlayPreferences = statusOverlay.decodePreferences() {
                preferences.statusOverlay = overlayPreferences
            } else {
                issues.append(.invalidStatusOverlay)
            }

            return DecodedPreferences(
                preferences: preferences,
                issues: issues,
                requiresSave: false
            )
        }
    }

    private struct StoredMicrophonePreferencesV1: Codable {
        let mode: String
        let target: StoredAudioTargetV1

        init(preferences: MicrophonePreferences) {
            switch preferences.mode {
            case .toggle:
                mode = "toggle"
            case .pushToTalk:
                mode = "pushToTalk"
            }
            target = StoredAudioTargetV1(selection: preferences.target)
        }

        func decodePreferences() -> MicrophonePreferences? {
            let decodedMode: MuteMode
            switch mode {
            case "toggle":
                decodedMode = .toggle
            case "pushToTalk":
                decodedMode = .pushToTalk
            default:
                return nil
            }
            guard let target = target.selection else { return nil }
            return MicrophonePreferences(mode: decodedMode, target: target)
        }
    }

    private struct StoredAudioTargetV1: Codable {
        let kind: String
        let deviceUID: String?
        let deviceName: String?

        init(selection: AudioTargetSelection) {
            switch selection {
            case .systemDefault:
                kind = "systemDefault"
                deviceUID = nil
                deviceName = nil
            case let .device(uid, name):
                kind = "device"
                deviceUID = uid
                deviceName = name
            case .allInputs:
                kind = "allInputs"
                deviceUID = nil
                deviceName = nil
            }
        }

        var selection: AudioTargetSelection? {
            switch kind {
            case "systemDefault" where deviceUID == nil && deviceName == nil:
                .systemDefault
            case "device":
                if let deviceUID,
                   !deviceUID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let deviceName {
                    .device(uid: deviceUID, name: deviceName)
                } else {
                    nil
                }
            case "allInputs" where deviceUID == nil && deviceName == nil:
                .allInputs
            default:
                nil
            }
        }
    }

    private struct StoredShortcutPreferencesV1: Codable {
        let primary: StoredHotKeyV1

        init(preferences: ShortcutPreferences) {
            primary = StoredHotKeyV1(configuration: preferences.primary)
        }

        func decodePreferences() -> ShortcutPreferences? {
            guard let primary = primary.configuration else { return nil }
            return ShortcutPreferences(primary: primary)
        }
    }

    private struct StoredHotKeyV1: Codable {
        private static let commandModifier: UInt32 = 1 << 0
        private static let controlModifier: UInt32 = 1 << 1
        private static let optionModifier: UInt32 = 1 << 2
        private static let shiftModifier: UInt32 = 1 << 3

        let keyCode: UInt32
        let keyLabel: String
        let modifierRawValue: UInt32

        init(configuration: GlobalHotKeyConfiguration) {
            keyCode = configuration.keyCode
            keyLabel = configuration.keyLabel
            var storedModifiers: UInt32 = 0
            if configuration.modifiers.contains(.command) {
                storedModifiers |= Self.commandModifier
            }
            if configuration.modifiers.contains(.control) {
                storedModifiers |= Self.controlModifier
            }
            if configuration.modifiers.contains(.option) {
                storedModifiers |= Self.optionModifier
            }
            if configuration.modifiers.contains(.shift) {
                storedModifiers |= Self.shiftModifier
            }
            modifierRawValue = storedModifiers
        }

        var configuration: GlobalHotKeyConfiguration? {
            let knownModifierMask = Self.commandModifier
                | Self.controlModifier
                | Self.optionModifier
                | Self.shiftModifier
            guard modifierRawValue & ~knownModifierMask == 0 else { return nil }

            var modifiers: GlobalHotKeyModifiers = []
            if modifierRawValue & Self.commandModifier != 0 {
                modifiers.insert(.command)
            }
            if modifierRawValue & Self.controlModifier != 0 {
                modifiers.insert(.control)
            }
            if modifierRawValue & Self.optionModifier != 0 {
                modifiers.insert(.option)
            }
            if modifierRawValue & Self.shiftModifier != 0 {
                modifiers.insert(.shift)
            }

            let configuration = GlobalHotKeyConfiguration(
                keyCode: keyCode,
                keyLabel: keyLabel,
                modifiers: modifiers
            )
            return configuration.isValid ? configuration : nil
        }
    }

    private struct StoredHUDPreferencesV1: Codable {
        let isEnabled: Bool

        init(preferences: HUDPreferences) {
            isEnabled = preferences.isEnabled
        }

        var preferences: HUDPreferences {
            HUDPreferences(isEnabled: isEnabled)
        }
    }

    private struct StoredHUDPreferencesV2: Codable {
        let isEnabled: Bool
        let size: String
        let horizontalPosition: String
        let verticalPosition: String
        let displayTarget: String
        let duration: String

        init(preferences: HUDPreferences) {
            isEnabled = preferences.isEnabled
            size = preferences.size.rawValue
            horizontalPosition = preferences.position.horizontal.rawValue
            verticalPosition = preferences.position.vertical.rawValue
            displayTarget = preferences.displayTarget.rawValue
            duration = preferences.duration.rawValue
        }

        func decodePreferences() -> HUDPreferences? {
            guard let size = HUDSize(rawValue: size),
                  let horizontalPosition = HUDHorizontalPosition(
                    rawValue: horizontalPosition
                  ),
                  let verticalPosition = HUDVerticalPosition(rawValue: verticalPosition),
                  let displayTarget = HUDDisplayTarget(rawValue: displayTarget),
                  let duration = HUDDuration(rawValue: duration) else {
                return nil
            }
            return HUDPreferences(
                isEnabled: isEnabled,
                size: size,
                position: HUDPosition(
                    horizontal: horizontalPosition,
                    vertical: verticalPosition
                ),
                displayTarget: displayTarget,
                duration: duration
            )
        }
    }

    private struct StoredStatusOverlayPreferencesV3: Codable {
        let isEnabled: Bool
        let visibility: String
        let contentStyle: String
        let size: String
        let displayTarget: StoredStatusOverlayDisplayTargetV3
        let position: NormalizedScreenPosition
        let togglesMuteOnClick: Bool

        init(preferences: StatusOverlayPreferences) {
            isEnabled = preferences.isEnabled
            visibility = preferences.visibility.rawValue
            contentStyle = preferences.contentStyle.rawValue
            size = preferences.size.rawValue
            displayTarget = StoredStatusOverlayDisplayTargetV3(
                target: preferences.displayTarget
            )
            position = preferences.position
            togglesMuteOnClick = preferences.togglesMuteOnClick
        }

        func decodePreferences() -> StatusOverlayPreferences? {
            guard let visibility = StatusOverlayVisibility(rawValue: visibility),
                  let contentStyle = StatusOverlayContentStyle(rawValue: contentStyle),
                  let size = StatusOverlaySize(rawValue: size),
                  let displayTarget = displayTarget.target,
                  position.x.isFinite,
                  position.y.isFinite,
                  (0...1).contains(position.x),
                  (0...1).contains(position.y) else {
                return nil
            }
            return StatusOverlayPreferences(
                isEnabled: isEnabled,
                visibility: visibility,
                contentStyle: contentStyle,
                size: size,
                displayTarget: displayTarget,
                position: position,
                togglesMuteOnClick: togglesMuteOnClick
            )
        }
    }

    private struct StoredStatusOverlayDisplayTargetV3: Codable {
        let kind: String
        let displayID: String?
        let lastKnownName: String?

        init(target: StatusOverlayDisplayTarget) {
            switch target {
            case .main:
                kind = "main"
                displayID = nil
                lastKnownName = nil
            case let .display(id, lastKnownName):
                kind = "display"
                displayID = id
                self.lastKnownName = lastKnownName
            }
        }

        var target: StatusOverlayDisplayTarget? {
            switch kind {
            case "main" where displayID == nil && lastKnownName == nil:
                .main
            case "display":
                if let displayID,
                   !displayID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let lastKnownName {
                    .display(id: displayID, lastKnownName: lastKnownName)
                } else {
                    nil
                }
            default:
                nil
            }
        }
    }

    private struct DecodedPreferences {
        let preferences: MuteletPreferences
        let issues: [PreferencesRecoveryIssue]
        let requiresSave: Bool
    }

    private let defaults: UserDefaults
    private let dataWriter: (@Sendable (Data) throws -> Void)?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(suiteName: String? = nil) {
        if let suiteName, let defaults = UserDefaults(suiteName: suiteName) {
            self.defaults = defaults
        } else {
            self.defaults = .standard
        }
        dataWriter = nil
    }

    init(
        suiteName: String?,
        dataWriter: @escaping @Sendable (Data) throws -> Void
    ) {
        if let suiteName, let defaults = UserDefaults(suiteName: suiteName) {
            self.defaults = defaults
        } else {
            self.defaults = .standard
        }
        self.dataWriter = dataWriter
    }

    public func load() -> PreferencesLoadResult {
        guard let storedValue = defaults.object(forKey: Self.storageKey) else {
            return .defaults
        }
        guard let data = storedValue as? Data else {
            return .recovered(MuteletPreferences(), issues: [.corruptedData])
        }

        let header: StoredPreferencesHeader
        do {
            header = try decoder.decode(StoredPreferencesHeader.self, from: data)
        } catch {
            return .recovered(MuteletPreferences(), issues: [.corruptedData])
        }

        var decoded: DecodedPreferences
        do {
            decoded = try decodePreferences(data, schemaVersion: header.schemaVersion)
        } catch let error as StoredPreferencesError {
            switch error {
            case let .unsupportedSchemaVersion(version):
                return .recovered(
                    MuteletPreferences(),
                    issues: [.unsupportedSchemaVersion(version)]
                )
            }
        } catch {
            return .recovered(MuteletPreferences(), issues: [.corruptedData])
        }

        if decoded.requiresSave {
            do {
                try save(decoded.preferences)
            } catch {
                decoded = DecodedPreferences(
                    preferences: decoded.preferences,
                    issues: decoded.issues + [.migrationSaveFailed],
                    requiresSave: false
                )
            }
        }

        return decoded.issues.isEmpty
            ? .loaded(decoded.preferences)
            : .recovered(decoded.preferences, issues: decoded.issues)
    }

    public func save(_ preferences: MuteletPreferences) throws {
        let data = try encoder.encode(StoredPreferencesV3(preferences: preferences))
        if let dataWriter {
            try dataWriter(data)
        } else {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private func decodePreferences(
        _ data: Data,
        schemaVersion: Int
    ) throws -> DecodedPreferences {
        switch schemaVersion {
        case 1:
            return try decoder
                .decode(StoredPreferencesV1.self, from: data)
                .decodePreferences()
        case 2:
            return try decoder
                .decode(StoredPreferencesV2.self, from: data)
                .decodePreferences()
        case Self.currentSchemaVersion:
            return try decoder
                .decode(StoredPreferencesV3.self, from: data)
                .decodePreferences()
        default:
            throw StoredPreferencesError.unsupportedSchemaVersion(schemaVersion)
        }
    }

    private enum StoredPreferencesError: Error {
        case unsupportedSchemaVersion(Int)
    }
}
