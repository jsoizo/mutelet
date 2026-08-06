import XCTest

final class MuteletUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testToggleMenuMutesFakeInput() throws {
        let app = launch(arguments: ["--ui-state=live"])
        openStatusMenu(in: app)

        let muteItem = app.menuItems["Mute"]
        XCTAssertTrue(muteItem.waitForExistence(timeout: 5))
        muteItem.click()

        openStatusMenu(in: app)
        XCTAssertTrue(
            app.menuItems["Microphone muted — UI Test Microphone"]
                .waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testPushToTalkMenuShowsHoldInstruction() throws {
        let app = launch(arguments: ["--ui-push-to-talk"])
        openStatusMenu(in: app)

        XCTAssertTrue(app.menuItems["Hold ⌃⌥M to talk"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testUnavailableInputIsReported() throws {
        let app = launch(arguments: ["--ui-no-input"])
        openStatusMenu(in: app)

        XCTAssertTrue(app.menuItems["No input device"].waitForExistence(timeout: 5))
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
        statusItem.click()
    }
}
