import Carbon
import XCTest
@testable import MuteletCore

final class MuteletPreferencesTests: XCTestCase {
    private static let storageKey = "muteletPreferences"
    private static let legacyStorageKey = "muteletPreferences.v1"

    private struct StoredPreferencesHeader: Codable {
        let schemaVersion: Int
    }

    private enum StubPreferencesError: Error {
        case saveFailed
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
            hud: HUDPreferences(
                isEnabled: false,
                size: .large,
                position: HUDPosition(horizontal: .trailing, vertical: .top),
                displayTarget: .all,
                duration: .long
            ),
            statusOverlay: StatusOverlayPreferences(
                isEnabled: true,
                visibility: .whenPotentiallyLive,
                contentStyle: .iconAndStatus,
                size: .compact,
                displayTarget: .display(id: "display-uuid", lastKnownName: "Studio Display"),
                position: NormalizedScreenPosition(x: 0.25, y: 0.75),
                togglesMuteOnClick: true
            )
        )
        let fixture = Data(
            #"""
            {
              "schemaVersion": 3,
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
              "hud": {
                "isEnabled": false,
                "size": "large",
                "horizontalPosition": "trailing",
                "verticalPosition": "top",
                "displayTarget": "all",
                "duration": "long"
              },
              "statusOverlay": {
                "isEnabled": true,
                "visibility": "whenPotentiallyLive",
                "contentStyle": "iconAndStatus",
                "size": "compact",
                "displayTarget": {
                  "kind": "display",
                  "displayID": "display-uuid",
                  "lastKnownName": "Studio Display"
                },
                "position": { "x": 0.25, "y": 0.75 },
                "togglesMuteOnClick": true
              }
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
        XCTAssertEqual(header.schemaVersion, 3)
        XCTAssertEqual(
            try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSDictionary),
            try XCTUnwrap(JSONSerialization.jsonObject(with: fixture) as? NSDictionary)
        )
        XCTAssertNil(defaults.data(forKey: Self.legacyStorageKey))
    }

    func testVersionOnePreferencesMigrateToVersionThree() async throws {
        let suiteName = "MuteletPreferencesTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
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

        let actual = await UserDefaultsMuteletPreferencesStore(
            suiteName: suiteName
        ).load()

        XCTAssertEqual(
            actual,
            .loaded(
                MuteletPreferences(
                    microphone: MicrophonePreferences(
                        mode: .pushToTalk,
                        target: .allInputs
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
            )
        )
        let migratedData = try XCTUnwrap(defaults.data(forKey: Self.storageKey))
        XCTAssertEqual(
            try JSONDecoder().decode(StoredPreferencesHeader.self, from: migratedData)
                .schemaVersion,
            3
        )
        let reloaded = await UserDefaultsMuteletPreferencesStore(
            suiteName: suiteName
        ).load()
        XCTAssertEqual(reloaded, actual)
    }

    func testVersionOneMigrationReportsSaveFailure() async throws {
        let suiteName = "MuteletPreferencesTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(
            Data(
                #"""
                {
                  "schemaVersion": 1,
                  "microphone": {
                    "mode": "toggle",
                    "target": { "kind": "systemDefault" }
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
                """#.utf8
            ),
            forKey: Self.storageKey
        )
        let store = UserDefaultsMuteletPreferencesStore(
            suiteName: suiteName,
            dataWriter: { _ in throw StubPreferencesError.saveFailed }
        )

        let actual = await store.load()

        XCTAssertEqual(
            actual,
            .recovered(
                MuteletPreferences(hud: HUDPreferences(isEnabled: false)),
                issues: [.migrationSaveFailed]
            )
        )
        let unchangedData = try XCTUnwrap(defaults.data(forKey: Self.storageKey))
        XCTAssertEqual(
            try JSONDecoder().decode(StoredPreferencesHeader.self, from: unchangedData)
                .schemaVersion,
            1
        )
    }

    func testVersionTwoPreferencesMigrateToVersionThree() async throws {
        let suiteName = "MuteletPreferencesTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(
            Data(
                #"""
                {
                  "schemaVersion": 2,
                  "microphone": {
                    "mode": "toggle",
                    "target": { "kind": "systemDefault" }
                  },
                  "shortcuts": {
                    "primary": {
                      "keyCode": 46,
                      "keyLabel": "M",
                      "modifierRawValue": 10
                    }
                  },
                  "hud": {
                    "isEnabled": false,
                    "size": "large",
                    "horizontalPosition": "trailing",
                    "verticalPosition": "bottom",
                    "displayTarget": "main",
                    "duration": "long"
                  }
                }
                """#.utf8
            ),
            forKey: Self.storageKey
        )
        let store = UserDefaultsMuteletPreferencesStore(suiteName: suiteName)

        let actual = await store.load()

        XCTAssertEqual(
            actual,
            .loaded(
                MuteletPreferences(
                    hud: HUDPreferences(
                        isEnabled: false,
                        size: .large,
                        position: HUDPosition(horizontal: .trailing, vertical: .bottom),
                        displayTarget: .main,
                        duration: .long
                    )
                )
            )
        )
        let migratedData = try XCTUnwrap(defaults.data(forKey: Self.storageKey))
        XCTAssertEqual(
            try JSONDecoder().decode(StoredPreferencesHeader.self, from: migratedData)
                .schemaVersion,
            3
        )
    }

    func testHUDDefaultsMatchExistingPresentation() {
        let hud = HUDPreferences()

        XCTAssertTrue(hud.isEnabled)
        XCTAssertEqual(hud.size, .standard)
        XCTAssertEqual(hud.position, HUDPosition())
        XCTAssertEqual(hud.displayTarget, .pointer)
        XCTAssertEqual(hud.duration, .standard)
    }

    func testStatusOverlayDefaults() {
        let overlay = StatusOverlayPreferences()

        XCTAssertFalse(overlay.isEnabled)
        XCTAssertEqual(overlay.visibility, .always)
        XCTAssertEqual(overlay.contentStyle, .iconOnly)
        XCTAssertEqual(overlay.size, .standard)
        XCTAssertEqual(overlay.displayTarget, .main)
        XCTAssertEqual(overlay.position, NormalizedScreenPosition(x: 1, y: 0.5))
        XCTAssertFalse(overlay.togglesMuteOnClick)
    }

    func testEachStatusOverlaySettingValueRoundTrips() async throws {
        let suiteName = "MuteletPreferencesTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsMuteletPreferencesStore(suiteName: suiteName)
        var values = StatusOverlayVisibility.allCases.map {
            StatusOverlayPreferences(visibility: $0)
        }
        values += StatusOverlayContentStyle.allCases.map {
            StatusOverlayPreferences(contentStyle: $0)
        }
        values += StatusOverlaySize.allCases.map {
            StatusOverlayPreferences(size: $0)
        }
        values += [
            StatusOverlayPreferences(displayTarget: .main),
            StatusOverlayPreferences(
                displayTarget: .display(id: "display-uuid", lastKnownName: "Display")
            ),
            StatusOverlayPreferences(
                isEnabled: true,
                position: NormalizedScreenPosition(x: 0, y: 1),
                togglesMuteOnClick: true
            ),
        ]

        for statusOverlay in values {
            let preferences = MuteletPreferences(statusOverlay: statusOverlay)
            try await store.save(preferences)
            let loaded = await store.load()
            XCTAssertEqual(loaded, .loaded(preferences))
        }
    }

    func testStatusOverlayVisibilityForEveryStatus() {
        let statuses: [(MuteStatus, Bool)] = [
            (.loading, true),
            (.live(deviceName: "Mic"), true),
            (.muted(deviceName: "Mic"), false),
            (.mixed(deviceName: "Mic"), true),
            (.unavailable, false),
            (.disconnected(deviceName: "Mic"), false),
            (.unsupported(deviceName: "Mic"), true),
            (.partial(deviceName: "All", muted: 1, live: 0, mixed: 0, unsupported: 0, failed: 0), true),
            (.error(message: "Failed"), true),
        ]

        for (status, potentiallyLive) in statuses {
            XCTAssertTrue(StatusOverlayVisibility.always.includes(status))
            XCTAssertEqual(
                StatusOverlayVisibility.whenPotentiallyLive.includes(status),
                potentiallyLive
            )
        }
    }

    func testEachHUDSettingValueRoundTrips() async throws {
        let suiteName = "MuteletPreferencesTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsMuteletPreferencesStore(suiteName: suiteName)
        var values: [HUDPreferences] = []

        values += HUDSize.allCases.map { HUDPreferences(size: $0) }
        values += HUDDisplayTarget.allCases.map { HUDPreferences(displayTarget: $0) }
        values += HUDDuration.allCases.map { HUDPreferences(duration: $0) }
        for vertical in HUDVerticalPosition.allCases {
            for horizontal in HUDHorizontalPosition.allCases {
                values.append(
                    HUDPreferences(
                        position: HUDPosition(
                            horizontal: horizontal,
                            vertical: vertical
                        )
                    )
                )
            }
        }

        for hud in values {
            let preferences = MuteletPreferences(hud: hud)
            try await store.save(preferences)
            let loaded = await store.load()
            XCTAssertEqual(loaded, .loaded(preferences))
        }
    }

    func testInvalidStoredHUDRecoversOnlyHUDGroup() async throws {
        let suiteName = "MuteletPreferencesTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(
            Data(
                #"""
                {
                  "schemaVersion": 2,
                  "microphone": {
                    "mode": "pushToTalk",
                    "target": { "kind": "allInputs" }
                  },
                  "shortcuts": {
                    "primary": {
                      "keyCode": 49,
                      "keyLabel": "Space",
                      "modifierRawValue": 9
                    }
                  },
                  "hud": {
                    "isEnabled": false,
                    "size": "enormous",
                    "horizontalPosition": "center",
                    "verticalPosition": "center",
                    "displayTarget": "pointer",
                    "duration": "standard"
                  }
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
                    microphone: MicrophonePreferences(
                        mode: .pushToTalk,
                        target: .allInputs
                    ),
                    shortcuts: ShortcutPreferences(
                        primary: GlobalHotKeyConfiguration(
                            keyCode: 49,
                            keyLabel: "Space",
                            modifiers: [.command, .shift]
                        )
                    )
                ),
                issues: [.invalidHUD]
            )
        )
    }

    func testInvalidStatusOverlayRecoversOnlyStatusOverlayGroup() async throws {
        let suiteName = "MuteletPreferencesTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(
            Data(
                #"""
                {
                  "schemaVersion": 3,
                  "microphone": {
                    "mode": "pushToTalk",
                    "target": { "kind": "allInputs" }
                  },
                  "shortcuts": {
                    "primary": {
                      "keyCode": 49,
                      "keyLabel": "Space",
                      "modifierRawValue": 9
                    }
                  },
                  "hud": {
                    "isEnabled": false,
                    "size": "large",
                    "horizontalPosition": "trailing",
                    "verticalPosition": "top",
                    "displayTarget": "all",
                    "duration": "long"
                  },
                  "statusOverlay": {
                    "isEnabled": true,
                    "visibility": "always",
                    "contentStyle": "iconOnly",
                    "size": "standard",
                    "displayTarget": {
                      "kind": "display",
                      "displayID": "",
                      "lastKnownName": "Display"
                    },
                    "position": { "x": 1.2, "y": 0.5 },
                    "togglesMuteOnClick": true
                  }
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
                    microphone: MicrophonePreferences(
                        mode: .pushToTalk,
                        target: .allInputs
                    ),
                    shortcuts: ShortcutPreferences(
                        primary: GlobalHotKeyConfiguration(
                            keyCode: 49,
                            keyLabel: "Space",
                            modifiers: [.command, .shift]
                        )
                    ),
                    hud: HUDPreferences(
                        isEnabled: false,
                        size: .large,
                        position: HUDPosition(horizontal: .trailing, vertical: .top),
                        displayTarget: .all,
                        duration: .long
                    )
                ),
                issues: [.invalidStatusOverlay]
            )
        )
    }

    func testHUDLayoutCalculatesAllNinePositions() {
        let visibleFrame = CGRect(x: 100, y: 200, width: 1_200, height: 800)
        let panelSize = CGSize(width: 300, height: 168)
        let expectedX: [HUDHorizontalPosition: CGFloat] = [
            .leading: 132,
            .center: 550,
            .trailing: 968,
        ]
        let expectedY: [HUDVerticalPosition: CGFloat] = [
            .top: 800,
            .center: 516,
            .bottom: 232,
        ]

        for vertical in HUDVerticalPosition.allCases {
            for horizontal in HUDHorizontalPosition.allCases {
                let frame = HUDLayout.frame(
                    panelSize: panelSize,
                    in: visibleFrame,
                    position: HUDPosition(
                        horizontal: horizontal,
                        vertical: vertical
                    )
                )
                XCTAssertEqual(frame.origin.x, expectedX[horizontal]!)
                XCTAssertEqual(frame.origin.y, expectedY[vertical]!)
                XCTAssertTrue(visibleFrame.contains(frame))
            }
        }
    }

    func testHUDLayoutClampsToSmallVisibleFrame() {
        let visibleFrame = CGRect(x: -500, y: 40, width: 320, height: 200)
        let frame = HUDLayout.frame(
            panelSize: CGSize(width: 300, height: 168),
            in: visibleFrame,
            position: HUDPosition(horizontal: .trailing, vertical: .top)
        )

        XCTAssertEqual(frame, CGRect(x: -500, y: 40, width: 300, height: 168))
        XCTAssertTrue(visibleFrame.contains(frame))
    }

    func testHUDLayoutScalesLargePanelToFitVisibleFrame() {
        let visibleFrame = CGRect(x: 40, y: -100, width: 320, height: 200)
        let frame = HUDLayout.frame(
            panelSize: CGSize(width: 480, height: 288),
            in: visibleFrame,
            position: HUDPosition(horizontal: .center, vertical: .center)
        )

        XCTAssertEqual(frame, CGRect(x: 40, y: -96, width: 320, height: 192))
        XCTAssertTrue(visibleFrame.contains(frame))
    }

    func testHUDScreenTargetResolution() {
        let frames = [
            CGRect(x: 0, y: 0, width: 1_000, height: 800),
            CGRect(x: 1_000, y: -200, width: 1_200, height: 900),
        ]

        XCTAssertEqual(
            HUDLayout.screenIndices(
                for: .pointer,
                screenFrames: frames,
                mainScreenIndex: 0,
                pointerLocation: CGPoint(x: 1_500, y: 100)
            ),
            [1]
        )
        XCTAssertEqual(
            HUDLayout.screenIndices(
                for: .pointer,
                screenFrames: frames,
                mainScreenIndex: 1,
                pointerLocation: CGPoint(x: -100, y: -100)
            ),
            [1]
        )
        XCTAssertEqual(
            HUDLayout.screenIndices(
                for: .main,
                screenFrames: frames,
                mainScreenIndex: 1,
                pointerLocation: .zero
            ),
            [1]
        )
        XCTAssertEqual(
            HUDLayout.screenIndices(
                for: .all,
                screenFrames: frames,
                mainScreenIndex: 0,
                pointerLocation: .zero
            ),
            [0, 1]
        )
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
