import XCTest

final class MuteletUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testToggleMenuMutesFakeInput() throws {
        let app = launch(arguments: ["--ui-state=live"])
        openStatusMenu(in: app)

        let muteButton = app.buttons["mutelet-primary-action"]
        XCTAssertTrue(muteButton.waitForExistence(timeout: 5))
        XCTAssertEqual(muteButton.label, "Mute")
        muteButton.click()

        let hud = app.descendants(matching: .any)["mutelet-hud"]
        XCTAssertTrue(hud.waitForExistence(timeout: 2))

        let status = app.descendants(matching: .any)["mutelet-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        waitForValue("Microphone muted — UI Test Microphone", on: status)
        waitForLabel("Unmute", on: muteButton)
    }

    @MainActor
    func testPushToTalkMenuShowsHoldInstruction() throws {
        let app = launch(arguments: ["--ui-push-to-talk"])
        openStatusMenu(in: app)

        let instruction = app.descendants(matching: .any)["mutelet-push-to-talk-instruction"]
        XCTAssertTrue(instruction.waitForExistence(timeout: 5))
        let status = app.descendants(matching: .any)["mutelet-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.value as? String, "Microphone muted — UI Test Microphone")

        app.buttons["UI Test Hot Key Press"].click()
        waitForValue("Microphone on — UI Test Microphone", on: status)

        app.buttons["UI Test Hot Key Release"].click()
        waitForValue("Microphone muted — UI Test Microphone", on: status)
    }

    @MainActor
    func testUnavailableInputIsReported() throws {
        let app = launch(arguments: ["--ui-no-input"])
        openStatusMenu(in: app)

        let status = app.descendants(matching: .any)["mutelet-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.value as? String, "No input device")
    }

    @MainActor
    func testPersistentStatusReflectsStateAndTogglesMute() throws {
        let app = launch(arguments: [
            "--ui-state=live",
            "--ui-hud-disabled",
            "--ui-status-overlay-enabled",
            "--ui-status-overlay-content=iconAndStatus",
            "--ui-status-overlay-size=large",
            "--ui-status-overlay-click-toggle",
        ])
        let overlay = app.descendants(matching: .any)["mutelet-status-overlay"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 5))
        XCTAssertEqual(overlay.label, "Microphone on — UI Test Microphone")
        XCTAssertGreaterThanOrEqual(overlay.frame.width, 170)
        XCTAssertLessThanOrEqual(overlay.frame.width, 182)

        overlay.click()

        waitForLabel("Microphone muted — UI Test Microphone", on: overlay)
    }

    @MainActor
    func testPersistentStatusCanBeEnabledAndResetFromSettings() throws {
        let app = launch(arguments: ["--ui-state=live"])
        openStatusMenu(in: app)
        let settingsLink = app.buttons["mutelet-settings-link"]
        XCTAssertTrue(settingsLink.waitForExistence(timeout: 5))
        settingsLink.click()

        let settingsWindow = app.windows["com_apple_SwiftUI_Settings_window"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))
        let generalTab = settingsWindow.buttons["General"]
        XCTAssertTrue(generalTab.waitForExistence(timeout: 2))
        generalTab.click()

        let enabled = app.descendants(matching: .any)["settings-status-overlay-enabled"]
        XCTAssertTrue(enabled.waitForExistence(timeout: 5))
        let overlay = app.descendants(matching: .any)["mutelet-status-overlay"]
        XCTAssertFalse(overlay.exists)
        enabled.click()

        XCTAssertTrue(overlay.waitForExistence(timeout: 5))
        let reset = app.buttons["settings-status-overlay-reset-position"]
        XCTAssertTrue(reset.waitForExistence(timeout: 2))
        reset.click()
        XCTAssertTrue(overlay.exists)
    }

    @MainActor
    func testSettingsWindowClosesPopoverAndReactivatesExistingWindow() throws {
        let app = launch(arguments: ["--ui-state=live"])
        openStatusMenu(in: app)

        let settingsLink = app.buttons["mutelet-settings-link"]
        let primaryAction = app.buttons["mutelet-primary-action"]
        XCTAssertTrue(settingsLink.waitForExistence(timeout: 5))
        settingsLink.click()

        let settingsWindow = app.windows["com_apple_SwiftUI_Settings_window"]
        if !settingsWindow.waitForExistence(timeout: 2) {
            XCTAssertTrue(settingsLink.waitForExistence(timeout: 2))
            settingsLink.click()
        }

        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))
        XCTAssertTrue(primaryAction.waitForNonExistence(timeout: 2))
        let generalTab = settingsWindow.buttons["General"]
        XCTAssertTrue(generalTab.waitForExistence(timeout: 2))
        generalTab.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["settings-show-hud"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.descendants(matching: .any)["settings-mode-picker"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["settings-input-picker"].exists)

        openStatusMenu(in: app)
        XCTAssertTrue(settingsLink.waitForExistence(timeout: 5))
        settingsLink.click()

        XCTAssertTrue(primaryAction.waitForNonExistence(timeout: 2))
        XCTAssertEqual(
            app.windows.matching(identifier: "com_apple_SwiftUI_Settings_window").count,
            1
        )
        settingsWindow.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(settingsWindow.waitForNonExistence(timeout: 2))
    }

    @MainActor
    func testRecoveredPreferencesWarningAppearsAndClearsAfterSave() throws {
        let app = launch(arguments: [
            "--ui-state=live",
            "--ui-preferences-recovered",
            "--ui-preferences-save-fails-once",
        ])
        openStatusMenu(in: app)

        let menuWarning = app.descendants(matching: .any)[
            "mutelet-preferences-recovery-warning"
        ]
        XCTAssertTrue(menuWarning.waitForExistence(timeout: 5))

        let settingsLink = app.buttons["mutelet-settings-link"]
        XCTAssertTrue(settingsLink.waitForExistence(timeout: 2))
        settingsLink.click()

        let settingsWindow = app.windows["com_apple_SwiftUI_Settings_window"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))
        let settingsWarning = app.descendants(matching: .any)[
            "settings-preferences-recovery-warning"
        ]
        XCTAssertTrue(settingsWarning.waitForExistence(timeout: 5))

        let hudToggle = app.descendants(matching: .any)["settings-show-hud"]
        XCTAssertTrue(hudToggle.waitForExistence(timeout: 2))
        hudToggle.click()
        XCTAssertTrue(settingsWarning.waitForExistence(timeout: 2))
        let saveError = app.descendants(matching: .any)["settings-preferences-save-error"]
        XCTAssertTrue(saveError.waitForExistence(timeout: 5))

        hudToggle.click()
        XCTAssertTrue(settingsWarning.waitForNonExistence(timeout: 5))
        XCTAssertTrue(saveError.waitForNonExistence(timeout: 2))

        openStatusMenu(in: app)
        XCTAssertTrue(menuWarning.waitForNonExistence(timeout: 2))
    }

    @MainActor
    func testDisabledCompactHUDCanBePreviewedFromSettings() throws {
        let app = launch(arguments: [
            "--ui-state=live",
            "--ui-hud-disabled",
            "--ui-hud-size=compact",
            "--ui-hud-position=top-leading",
            "--ui-hud-display-target=all",
            "--ui-hud-duration=long",
            "--ui-keep-hud-visible",
        ])
        openStatusMenu(in: app)
        let settingsLink = app.buttons["mutelet-settings-link"]
        XCTAssertTrue(settingsLink.waitForExistence(timeout: 5))
        settingsLink.click()

        let settingsWindow = app.windows["com_apple_SwiftUI_Settings_window"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.buttons["mutelet-primary-action"]
                .waitForNonExistence(timeout: 2)
        )
        let generalTab = settingsWindow.buttons["General"]
        XCTAssertTrue(generalTab.waitForExistence(timeout: 2))
        generalTab.click()
        let hudToggle = app.descendants(matching: .any)["settings-show-hud"]
        XCTAssertTrue(hudToggle.waitForExistence(timeout: 5))
        assertValue("0", on: hudToggle)
        let sizePicker = app.descendants(matching: .any)["settings-hud-size"]
        XCTAssertTrue(sizePicker.waitForExistence(timeout: 2))
        let compactSize = sizePicker.descendants(matching: .any)["Compact"]
        XCTAssertTrue(compactSize.waitForExistence(timeout: 2))
        assertValue("1", on: compactSize)

        let durationPicker = app.descendants(matching: .any)["settings-hud-duration"]
        XCTAssertTrue(durationPicker.waitForExistence(timeout: 2))
        let longDuration = durationPicker.descendants(matching: .any)[
            "Long (2 seconds)"
        ]
        XCTAssertTrue(longDuration.waitForExistence(timeout: 2))
        assertValue("1", on: longDuration)

        let topLeading = app.descendants(matching: .any)[
            "settings-hud-position-top-leading"
        ]
        XCTAssertTrue(topLeading.waitForExistence(timeout: 2))
        XCTAssertTrue(topLeading.isSelected)

        let screenPicker = app.descendants(matching: .any)["settings-hud-screen"]
        XCTAssertTrue(screenPicker.waitForExistence(timeout: 2))
        XCTAssertEqual(screenPicker.value as? String, "All screens")

        let preview = app.buttons["settings-hud-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 2))
        preview.click()

        let hud = app.descendants(matching: .any)["mutelet-hud"]
        XCTAssertTrue(hud.waitForExistence(timeout: 2))
        assertValue("Microphone on", on: hud)
        XCTAssertGreaterThanOrEqual(hud.frame.width, 290)
        XCTAssertLessThanOrEqual(hud.frame.width, 310)

        let largeSize = sizePicker.descendants(matching: .any)["Large"]
        XCTAssertTrue(largeSize.waitForExistence(timeout: 2))
        largeSize.click()
        assertValue("1", on: largeSize)

        let bottomTrailing = app.descendants(matching: .any)[
            "settings-hud-position-bottom-trailing"
        ]
        XCTAssertTrue(bottomTrailing.waitForExistence(timeout: 2))
        bottomTrailing.click()
        XCTAssertTrue(bottomTrailing.isSelected)

        screenPicker.click()
        let mainScreen = app.menuItems["Main screen"]
        XCTAssertTrue(mainScreen.waitForExistence(timeout: 2))
        mainScreen.click()
        XCTAssertEqual(screenPicker.value as? String, "Main screen")

        let shortDuration = durationPicker.descendants(matching: .any)[
            "Short (0.5 seconds)"
        ]
        XCTAssertTrue(shortDuration.waitForExistence(timeout: 2))
        shortDuration.click()
        assertValue("1", on: shortDuration)
        assertValue("0", on: hudToggle)
    }

    @MainActor
    func testCaptureWebsiteAssets() throws {
        let captures = [
            (locale: "en_US", language: "en", deviceName: "MacBook Microphone"),
            (locale: "ja_JP", language: "ja", deviceName: "MacBookのマイク"),
        ]

        for capture in captures {
            let app = launch(
                arguments: [
                    "--ui-capture",
                    "--ui-state=live",
                    "--ui-device-name=\(capture.deviceName)",
                ],
                locale: capture.locale
            )
            openStatusMenu(in: app)

            let primaryAction = app.buttons["mutelet-primary-action"]
            XCTAssertTrue(primaryAction.waitForExistence(timeout: 5))
            let menuGroup = try websiteMenuGroup(in: app)
            attach(
                menuGroup.screenshot(),
                name: "toggle-\(capture.language)-0"
            )

            let initialLabel = primaryAction.label
            primaryAction.click()
            let labelChanged = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label != %@", initialLabel),
                object: primaryAction
            )
            XCTAssertEqual(
                XCTWaiter.wait(for: [labelChanged], timeout: 5),
                .completed
            )
            attach(
                menuGroup.screenshot(),
                name: "toggle-\(capture.language)-1"
            )
            app.terminate()
        }
    }

    @MainActor
    func testCaptureWebsiteHUDAssets() throws {
        let captures = [
            (locale: "en_US", language: "en", deviceName: "MacBook Microphone"),
            (locale: "ja_JP", language: "ja", deviceName: "MacBookのマイク"),
        ]

        for capture in captures {
            let hudApp = launch(
                arguments: [
                    "--ui-capture-hud",
                    "--ui-state=live",
                    "--ui-device-name=\(capture.deviceName)",
                ],
                locale: capture.locale
            )
            XCTAssertTrue(hudApp.statusItems.firstMatch.waitForExistence(timeout: 5))
            for frame in 0..<38 {
                attach(
                    XCUIScreen.main.screenshot(),
                    name: String(
                        format: "hud-%@-%02d",
                        capture.language,
                        frame
                    )
                )
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
            }
            hudApp.terminate()
        }
    }

    @MainActor
    private func launch(
        arguments: [String],
        locale: String = "en_US"
    ) -> XCUIApplication {
        let language = locale.hasPrefix("ja") ? "ja" : "en"
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale,
        ] + arguments
        app.launch()
        return app
    }

    @MainActor
    private func websiteMenuGroup(in app: XCUIApplication) throws -> XCUIElement {
        try XCTUnwrap(
            app.groups.allElementsBoundByIndex.first { group in
                let frame = group.frame
                return frame.width >= 300
                    && frame.width <= 400
                    && frame.height >= 250
            },
            "Mutelet menu group was not found"
        )
    }

    private func attach(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func openStatusMenu(in app: XCUIApplication) {
        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        let primaryAction = app.buttons["mutelet-primary-action"]
        let settingsLink = app.buttons["mutelet-settings-link"]
        for _ in 0..<2 {
            statusItem.click()
            if primaryAction.waitForExistence(timeout: 2),
               settingsLink.waitForExistence(timeout: 2) {
                return
            }
        }
        XCTFail("Mutelet status popover did not open")
    }

    @MainActor
    private func waitForLabel(_ label: String, on element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", label),
            object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    @MainActor
    private func waitForValue(_ value: String, on element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", value),
            object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    @MainActor
    private func assertValue(
        _ expected: String,
        on element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            element.value.map { String(describing: $0) },
            expected,
            file: file,
            line: line
        )
    }
}
