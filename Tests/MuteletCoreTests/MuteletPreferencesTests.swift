import Carbon
import XCTest
@testable import MuteletCore

final class MuteletPreferencesTests: XCTestCase {
    private static let storageKey = "muteletPreferences"
    private static let legacyStorageKey = "muteletPreferences.v1"

    private struct StoredPreferencesHeader: Codable {
        let schemaVersion: Int
    }

    func testDuplicateHotKeyStatusHasSpecificError() {
        let duplicate = CarbonHotKeyError.registrationFailure(
            status: OSStatus(eventHotKeyExistsErr)
        )
        let other = CarbonHotKeyError.registrationFailure(status: -1)

        guard case .hotKeyAlreadyRegistered = duplicate else {
            return XCTFail("Expected a duplicate hot-key error")
        }
        guard case let .hotKeyRegistrationFailed(status) = other else {
            return XCTFail("Expected a generic hot-key registration error")
        }
        XCTAssertEqual(status, -1)
    }

    func testPreferencesRoundTripUsesStableKeyAndCurrentSchema() async throws {
        let suiteName = "MuteletPreferencesTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let store = UserDefaultsMuteletPreferencesStore(suiteName: suiteName)
        let expected = MuteletPreferences(
            microphone: MicrophonePreferences(
                mode: .pushToTalk,
                target: .device(uid: "usb-mic", name: "USB Mic")
            ),
            shortcuts: ShortcutPreferences(
                primary: GlobalHotKeyConfiguration(
                    keyCode: 49,
                    keyLabel: "Space",
                    modifiers: [.command, .shift]
                )
            ),
            hud: HUDPreferences(isEnabled: false)
        )
        let fixture = Data(
            #"""
            {
              "schemaVersion": 1,
              "microphone": {
                "mode": "pushToTalk",
                "target": {
                  "kind": "device",
                  "deviceUID": "usb-mic",
                  "deviceName": "USB Mic"
                }
              },
              "shortcuts": {
                "primary": {
                  "keyCode": 49,
                  "keyLabel": "Space",
                  "modifierRawValue": 9
                }
              },
              "hud": { "isEnabled": false }
            }
            """#.utf8
        )

        defaults.set(fixture, forKey: Self.storageKey)
        let fixtureActual = await store.load()
        XCTAssertEqual(fixtureActual, .loaded(expected))

        try await store.save(expected)
        let actual = await store.load()

        XCTAssertEqual(actual, .loaded(expected))
        let data = try XCTUnwrap(defaults.data(forKey: Self.storageKey))
        let header = try JSONDecoder().decode(StoredPreferencesHeader.self, from: data)
        XCTAssertEqual(header.schemaVersion, 1)
        XCTAssertEqual(
            try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSDictionary),
            try XCTUnwrap(JSONSerialization.jsonObject(with: fixture) as? NSDictionary)
        )
        XCTAssertNil(defaults.data(forKey: Self.legacyStorageKey))
    }

    func testMissingPreferencesReturnsDefaults() async {
        let suiteName = "MuteletPreferencesTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsMuteletPreferencesStore(suiteName: suiteName)

        let actual = await store.load()

        XCTAssertEqual(actual, .defaults)
    }

    func testCorruptedDataRecoversAllPreferences() async throws {
        let suiteName = "MuteletPreferencesTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(Data("not-json".utf8), forKey: Self.storageKey)
        let store = UserDefaultsMuteletPreferencesStore(suiteName: suiteName)
        let actual = await store.load()

        XCTAssertEqual(
            actual,
            .recovered(MuteletPreferences(), issues: [.corruptedData])
        )
    }

    func testNonDataStoredValueIsReportedAsCorrupted() async throws {
        let suiteName = "MuteletPreferencesTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set("not-data", forKey: Self.storageKey)
        let store = UserDefaultsMuteletPreferencesStore(suiteName: suiteName)

        let actual = await store.load()

        XCTAssertEqual(
            actual,
            .recovered(MuteletPreferences(), issues: [.corruptedData])
        )
    }

    func testUnsupportedSchemaVersionRecoversDefaultsWithVersion() async throws {
        let suiteName = "MuteletPreferencesTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(
            try JSONEncoder().encode(StoredPreferencesHeader(schemaVersion: 999)),
            forKey: Self.storageKey
        )
        let store = UserDefaultsMuteletPreferencesStore(suiteName: suiteName)
        let actual = await store.load()

        XCTAssertEqual(
            actual,
            .recovered(
                MuteletPreferences(),
                issues: [.unsupportedSchemaVersion(999)]
            )
        )
    }

    func testInvalidStoredShortcutRecoversOnlyShortcutGroup() async throws {
        let suiteName = "MuteletPreferencesTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let microphone = MicrophonePreferences(mode: .pushToTalk, target: .allInputs)
        let hud = HUDPreferences(isEnabled: false)
        defaults.set(
            Data(
                #"""
                {
                  "schemaVersion": 1,
                  "microphone": {
                    "mode": "pushToTalk",
                    "target": { "kind": "allInputs" }
                  },
                  "shortcuts": {
                    "primary": {
                      "keyCode": 46,
                      "keyLabel": "M",
                      "modifierRawValue": 6
                    }
                  },
                  "hud": { "isEnabled": false }
                }
                """#.utf8
            ),
            forKey: Self.storageKey
        )

        let actual = await UserDefaultsMuteletPreferencesStore(
            suiteName: suiteName
        ).load()

        XCTAssertEqual(
            actual,
            .recovered(
                MuteletPreferences(
                    microphone: microphone,
                    shortcuts: ShortcutPreferences(),
                    hud: hud
                ),
                issues: [.invalidShortcut]
            )
        )
    }

    func testInvalidStoredMicrophoneRecoversOnlyMicrophoneGroup() async throws {
        let suiteName = "MuteletPreferencesTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(
            Data(
                #"""
                {
                  "schemaVersion": 1,
                  "microphone": {
                    "mode": "futureMode",
                    "target": { "kind": "allInputs" }
                  },
                  "shortcuts": {
                    "primary": {
                      "keyCode": 49,
                      "keyLabel": "Space",
                      "modifierRawValue": 9
                    }
                  },
                  "hud": { "isEnabled": false }
                }
                """#.utf8
            ),
            forKey: Self.storageKey
        )
        let shortcuts = ShortcutPreferences(
            primary: GlobalHotKeyConfiguration(
                keyCode: 49,
                keyLabel: "Space",
                modifiers: [.command, .shift]
            )
        )

        let actual = await UserDefaultsMuteletPreferencesStore(
            suiteName: suiteName
        ).load()

        XCTAssertEqual(
            actual,
            .recovered(
                MuteletPreferences(
                    microphone: MicrophonePreferences(),
                    shortcuts: shortcuts,
                    hud: HUDPreferences(isEnabled: false)
                ),
                issues: [.invalidMicrophone]
            )
        )
    }

    func testInvalidStoredTargetsRecoverOnlyMicrophoneGroup() async throws {
        let suiteName = "MuteletPreferencesTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let store = UserDefaultsMuteletPreferencesStore(suiteName: suiteName)
        let invalidTargets = [
            #"{"kind":"device","deviceUID":"","deviceName":"USB Mic"}"#,
            #"{"kind":"futureTarget"}"#,
        ]

        for target in invalidTargets {
            let json = """
            {
              "schemaVersion": 1,
              "microphone": {
                "mode": "toggle",
                "target": \(target)
              },
              "shortcuts": {
                "primary": {
                  "keyCode": 46,
                  "keyLabel": "M",
                  "modifierRawValue": 10
                }
              },
              "hud": { "isEnabled": false }
            }
            """
            defaults.set(Data(json.utf8), forKey: Self.storageKey)

            let actual = await store.load()

            XCTAssertEqual(
                actual,
                .recovered(
                    MuteletPreferences(
                        microphone: MicrophonePreferences(),
                        shortcuts: ShortcutPreferences(),
                        hud: HUDPreferences(isEnabled: false)
                    ),
                    issues: [.invalidMicrophone]
                )
            )
        }
    }

    func testLegacyKeyIsIgnored() async throws {
        let suiteName = "MuteletPreferencesTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(Data("legacy".utf8), forKey: Self.legacyStorageKey)
        let store = UserDefaultsMuteletPreferencesStore(suiteName: suiteName)
        let actual = await store.load()

        XCTAssertEqual(actual, .defaults)
        XCTAssertEqual(defaults.data(forKey: Self.legacyStorageKey), Data("legacy".utf8))
    }

    func testShortcutRequiresCommandOrControl() {
        let invalid = GlobalHotKeyConfiguration(
            keyCode: 46,
            keyLabel: "M",
            modifiers: [.option, .shift]
        )

        XCTAssertFalse(invalid.isValid)
        XCTAssertTrue(GlobalHotKeyConfiguration.default.isValid)
        XCTAssertEqual(GlobalHotKeyConfiguration.default.displayName, "⌃⇧M")
        XCTAssertTrue(
            GlobalHotKeyConfiguration(
                keyCode: 8,
                keyLabel: "C",
                modifiers: [.command]
            ).isValid
        )
        XCTAssertTrue(
            GlobalHotKeyConfiguration(
                keyCode: 8,
                keyLabel: "C",
                modifiers: [.control]
            ).isValid
        )
        XCTAssertFalse(
            GlobalHotKeyConfiguration(
                keyCode: 8,
                keyLabel: "C",
                modifiers: []
            ).isValid
        )
        XCTAssertFalse(
            GlobalHotKeyConfiguration(
                keyCode: 46,
                keyLabel: "M",
                modifiers: [.control, .option]
            ).isValid
        )
    }
}
