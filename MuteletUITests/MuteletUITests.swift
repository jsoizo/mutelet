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
    private func launch(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ] + arguments
        app.launch()
        return app
    }

    @MainActor
    private func openStatusMenu(in app: XCUIApplication) {
        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        let primaryAction = app.buttons["mutelet-primary-action"]
        for _ in 0..<2 {
            statusItem.click()
            if primaryAction.waitForExistence(timeout: 2) {
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
}
