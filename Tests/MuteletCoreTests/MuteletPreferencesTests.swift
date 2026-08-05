import XCTest
@testable import MuteletCore

final class MuteletPreferencesTests: XCTestCase {
    func testPreferencesRoundTrip() async throws {
        let suiteName = "MuteletPreferencesTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsMuteletPreferencesStore(suiteName: suiteName)
        let expected = MuteletPreferences(
            mode: .pushToTalk,
            target: .device(uid: "usb-mic", name: "USB Mic"),
            hotKey: GlobalHotKeyConfiguration(
                keyCode: 49,
                keyLabel: "Space",
                modifiers: [.command, .shift]
            ),
            showsHUD: false
        )

        try await store.save(expected)
        let actual = await store.load()

        XCTAssertEqual(actual, expected)
    }

    func testUnknownSchemaVersionFallsBackToDefaults() async throws {
        let suiteName = "MuteletPreferencesTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        var futurePreferences = MuteletPreferences(mode: .pushToTalk)
        futurePreferences.schemaVersion = 999
        defaults.set(
            try JSONEncoder().encode(futurePreferences),
            forKey: "muteletPreferences.v1"
        )
        let store = UserDefaultsMuteletPreferencesStore(suiteName: suiteName)

        let actual = await store.load()

        XCTAssertEqual(actual, MuteletPreferences())
    }

    func testShortcutRequiresCommandOrControl() {
        let invalid = GlobalHotKeyConfiguration(
            keyCode: 46,
            keyLabel: "M",
            modifiers: [.option, .shift]
        )

        XCTAssertFalse(invalid.isValid)
        XCTAssertTrue(GlobalHotKeyConfiguration.default.isValid)
        XCTAssertEqual(GlobalHotKeyConfiguration.default.displayName, "⌃⌥M")
    }
}
