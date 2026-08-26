import XCTest
@testable import MuteletCore

final class ScreenEdgeIndicatorTests: XCTestCase {
    private let enabled = ScreenEdgeIndicatorPreferences(isEnabled: true)
    private let enabledWithOutline = ScreenEdgeIndicatorPreferences(
        isEnabled: true,
        showsIdleOutline: true
    )

    private func appearance(
        _ status: MuteStatus,
        mode: MuteMode = .pushToTalk,
        preferences: ScreenEdgeIndicatorPreferences? = nil
    ) -> ScreenEdgeAppearance {
        ScreenEdgeIndicatorPresentation.appearance(
            mode: mode,
            status: status,
            preferences: preferences ?? enabled
        )
    }

    func testDisabledPreferencesNeverShowTheEdge() {
        XCTAssertEqual(
            appearance(.live(deviceName: "Mic"), preferences: ScreenEdgeIndicatorPreferences()),
            .hidden
        )
    }

    func testToggleModeNeverShowsTheEdge() {
        XCTAssertEqual(appearance(.live(deviceName: "Mic"), mode: .toggle), .hidden)
        XCTAssertEqual(
            appearance(
                .live(deviceName: "Mic"),
                mode: .toggle,
                preferences: enabledWithOutline
            ),
            .hidden
        )
    }

    func testLiveStatusGlows() {
        XCTAssertEqual(appearance(.live(deviceName: "Mic")), .live)
    }

    func testStatesThatMayStillCarrySoundWarn() {
        XCTAssertEqual(appearance(.mixed(deviceName: "Mic")), .warning)
        XCTAssertEqual(appearance(.unsupported(deviceName: "Mic")), .warning)
        XCTAssertEqual(appearance(.externallySilenced(deviceName: "Mic")), .warning)
        XCTAssertEqual(appearance(.error(message: "failed")), .warning)
        XCTAssertEqual(
            appearance(
                .partial(
                    deviceName: "Mic",
                    muted: 1,
                    live: 1,
                    mixed: 0,
                    unsupported: 0,
                    failed: 0
                )
            ),
            .warning
        )
    }

    func testUnsupportedWarnsEvenWithoutTheIdleOutline() {
        // A device without a mute control is audible between gestures, so the warning is not
        // the idle outline in disguise and must survive with the outline turned off.
        XCTAssertEqual(appearance(.unsupported(deviceName: "Mic")), .warning)
    }

    func testMutedStatesAreHiddenUnlessTheIdleOutlineIsRequested() {
        for status in [
            MuteStatus.muted(deviceName: "Mic"),
            .unavailable,
            .disconnected(deviceName: "Mic"),
            .loading,
        ] {
            XCTAssertEqual(appearance(status), .hidden)
            XCTAssertEqual(
                appearance(status, preferences: enabledWithOutline),
                .idleOutline
            )
        }
    }

    func testLoadingNeverGlowsEvenWithTheIdleOutline() {
        XCTAssertNotEqual(appearance(.loading, preferences: enabledWithOutline), .live)
    }

    func testOnlyResolvableTargetsAreExpressedByTheEdge() {
        XCTAssertTrue(
            ScreenEdgeIndicatorPresentation.expressesGestureResult(.live(deviceName: "Mic"))
        )
        XCTAssertTrue(
            ScreenEdgeIndicatorPresentation.expressesGestureResult(.muted(deviceName: "Mic"))
        )
        XCTAssertTrue(
            ScreenEdgeIndicatorPresentation
                .expressesGestureResult(.unsupported(deviceName: "Mic"))
        )
        XCTAssertTrue(
            ScreenEdgeIndicatorPresentation
                .expressesGestureResult(.externallySilenced(deviceName: "Mic"))
        )
        XCTAssertFalse(ScreenEdgeIndicatorPresentation.expressesGestureResult(.unavailable))
        XCTAssertFalse(
            ScreenEdgeIndicatorPresentation
                .expressesGestureResult(.disconnected(deviceName: "Mic"))
        )
        XCTAssertFalse(ScreenEdgeIndicatorPresentation.expressesGestureResult(.loading))
    }

    func testHotKeyHUDIsSuppressedOnlyForPushToTalkWithTheEdgeEnabled() {
        XCTAssertTrue(
            ScreenEdgeIndicatorPresentation.suppressesHotKeyHUD(
                mode: .pushToTalk,
                preferences: enabled
            )
        )
        XCTAssertFalse(
            ScreenEdgeIndicatorPresentation.suppressesHotKeyHUD(
                mode: .toggle,
                preferences: enabled
            )
        )
        XCTAssertFalse(
            ScreenEdgeIndicatorPresentation.suppressesHotKeyHUD(
                mode: .pushToTalk,
                preferences: ScreenEdgeIndicatorPreferences()
            )
        )
    }
}
