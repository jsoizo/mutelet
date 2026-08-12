import AppKit
import XCTest
@testable import MuteletCore

final class StatusOverlayControllerTests: XCTestCase {
    func testAllContentAndSizeCombinationsHaveSpecifiedDimensions() {
        let expected: [StatusOverlayContentStyle: [StatusOverlaySize: CGSize]] = [
            .iconOnly: [
                .compact: CGSize(width: 32, height: 32),
                .standard: CGSize(width: 44, height: 44),
                .large: CGSize(width: 56, height: 56),
            ],
            .iconAndStatus: [
                .compact: CGSize(width: 112, height: 32),
                .standard: CGSize(width: 144, height: 44),
                .large: CGSize(width: 176, height: 56),
            ],
        ]

        for contentStyle in StatusOverlayContentStyle.allCases {
            for size in StatusOverlaySize.allCases {
                XCTAssertEqual(
                    StatusOverlayLayout.panelSize(contentStyle: contentStyle, size: size),
                    expected[contentStyle]?[size]
                )
            }
        }
    }

    func testNormalizedPositionRoundTripsAcrossVisibleFrames() {
        let visibleFrames = [
            CGRect(x: 0, y: 40, width: 1_440, height: 860),
            CGRect(x: -1_920, y: -200, width: 1_920, height: 1_080),
        ]
        let positions = [
            NormalizedScreenPosition(x: 0, y: 0),
            NormalizedScreenPosition(x: 0.25, y: 0.75),
            NormalizedScreenPosition(x: 1, y: 0.5),
        ]
        let size = CGSize(width: 176, height: 56)

        for visibleFrame in visibleFrames {
            for position in positions {
                let frame = StatusOverlayLayout.frame(
                    position: position,
                    panelSize: size,
                    visibleFrame: visibleFrame
                )
                let roundTrip = StatusOverlayLayout.normalizedPosition(
                    for: CGPoint(x: frame.midX, y: frame.midY),
                    panelSize: size,
                    visibleFrame: visibleFrame
                )
                XCTAssertEqual(roundTrip.x, position.x, accuracy: 0.000_001)
                XCTAssertEqual(roundTrip.y, position.y, accuracy: 0.000_001)
                XCTAssertGreaterThanOrEqual(frame.minX, visibleFrame.minX + 12)
                XCTAssertLessThanOrEqual(frame.maxX, visibleFrame.maxX - 12)
                XCTAssertGreaterThanOrEqual(frame.minY, visibleFrame.minY + 12)
                XCTAssertLessThanOrEqual(frame.maxY, visibleFrame.maxY - 12)
            }
        }
    }

    func testSizeChangeCanPreserveAbsoluteCenter() {
        let visibleFrame = CGRect(x: 100, y: 200, width: 1_200, height: 800)
        let originalSize = CGSize(width: 44, height: 44)
        let newSize = CGSize(width: 176, height: 56)
        let originalFrame = StatusOverlayLayout.frame(
            position: NormalizedScreenPosition(x: 0.4, y: 0.6),
            panelSize: originalSize,
            visibleFrame: visibleFrame
        )
        let center = CGPoint(x: originalFrame.midX, y: originalFrame.midY)
        let newPosition = StatusOverlayLayout.normalizedPosition(
            for: center,
            panelSize: newSize,
            visibleFrame: visibleFrame
        )
        let newFrame = StatusOverlayLayout.frame(
            position: newPosition,
            panelSize: newSize,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(newFrame.midX, center.x, accuracy: 0.000_001)
        XCTAssertEqual(newFrame.midY, center.y, accuracy: 0.000_001)
    }

    func testDragThresholdUsesFourPointEuclideanDistance() {
        XCTAssertFalse(
            StatusOverlayLayout.isDrag(from: .zero, to: CGPoint(x: 3.99, y: 0))
        )
        XCTAssertTrue(
            StatusOverlayLayout.isDrag(from: .zero, to: CGPoint(x: 4, y: 0))
        )
        XCTAssertTrue(
            StatusOverlayLayout.isDrag(from: .zero, to: CGPoint(x: 3, y: 3))
        )
    }

    func testIntersectionAreaSupportsDisplaySelection() {
        let panel = CGRect(x: 900, y: 100, width: 300, height: 100)
        let leftScreen = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let rightScreen = CGRect(x: 1_000, y: 0, width: 1_200, height: 900)

        XCTAssertEqual(StatusOverlayLayout.intersectionArea(panel, leftScreen), 10_000)
        XCTAssertEqual(StatusOverlayLayout.intersectionArea(panel, rightScreen), 20_000)
    }

    func testPresentationDecisionHidesDisabledOverlayImmediately() {
        XCTAssertEqual(
            StatusOverlayPresentationDecision.resolve(
                preferences: StatusOverlayPreferences(isEnabled: false),
                status: .live(deviceName: "Mic"),
                isSuspended: false,
                isDragging: false,
                hasResolvedScreen: true
            ),
            .hideImmediately
        )
    }

    func testPresentationDecisionKeepsDragPositionDuringStateUpdates() {
        XCTAssertEqual(
            StatusOverlayPresentationDecision.resolve(
                preferences: StatusOverlayPreferences(
                    isEnabled: true,
                    visibility: .whenPotentiallyLive
                ),
                status: .muted(deviceName: "Mic"),
                isSuspended: false,
                isDragging: true,
                hasResolvedScreen: true
            ),
            .updateContentOnly
        )
    }

    func testShowingAgainInvalidatesPendingHideCompletion() {
        var state = StatusOverlayVisibilityState()
        let hideGeneration = state.beginHide()

        state.invalidatePendingTransition()

        XCTAssertFalse(state.canCompleteHide(generation: hideGeneration))
    }

    func testDisplayTargetReconcilesLastKnownNameByUUID() {
        XCTAssertEqual(
            StatusOverlayDisplayTargetReconciler.reconcile(
                .display(id: "display-id", lastKnownName: "Old Name"),
                connectedNamesByID: ["display-id": "New Name"]
            ),
            .display(id: "display-id", lastKnownName: "New Name")
        )
        XCTAssertEqual(
            StatusOverlayDisplayTargetReconciler.reconcile(
                .display(id: "disconnected", lastKnownName: "Saved Name"),
                connectedNamesByID: ["display-id": "New Name"]
            ),
            .display(id: "disconnected", lastKnownName: "Saved Name")
        )
    }

    func testClickActionabilityRejectsDisabledPTTBusyAndUnsupportedStates() {
        let enabled = StatusOverlayPreferences(togglesMuteOnClick: true)
        let disabled = StatusOverlayPreferences(togglesMuteOnClick: false)
        let live = MuteStatus.live(deviceName: "Mic")

        XCTAssertTrue(
            StatusOverlayInteraction.isActionable(
                preferences: enabled,
                mode: .toggle,
                status: live,
                isBusy: false,
                isClickInFlight: false
            )
        )
        XCTAssertFalse(
            StatusOverlayInteraction.isActionable(
                preferences: disabled,
                mode: .toggle,
                status: live,
                isBusy: false,
                isClickInFlight: false
            )
        )
        XCTAssertFalse(
            StatusOverlayInteraction.isActionable(
                preferences: enabled,
                mode: .pushToTalk,
                status: live,
                isBusy: false,
                isClickInFlight: false
            )
        )
        XCTAssertFalse(
            StatusOverlayInteraction.isActionable(
                preferences: enabled,
                mode: .toggle,
                status: live,
                isBusy: true,
                isClickInFlight: false
            )
        )
        XCTAssertFalse(
            StatusOverlayInteraction.isActionable(
                preferences: enabled,
                mode: .toggle,
                status: .unsupported(deviceName: "Mic"),
                isBusy: false,
                isClickInFlight: false
            )
        )
        XCTAssertFalse(
            StatusOverlayInteraction.isActionable(
                preferences: enabled,
                mode: .toggle,
                status: live,
                isBusy: false,
                isClickInFlight: true
            )
        )
    }

    func testEveryStatusHasTheSpecifiedEnglishShortTitle() {
        let values: [(MuteStatus, String)] = [
            (.live(deviceName: "Mic"), "Live"),
            (.muted(deviceName: "Mic"), "Muted"),
            (.mixed(deviceName: "Mic"), "Mixed"),
            (.loading, "Checking…"),
            (.unavailable, "No input"),
            (.disconnected(deviceName: "Mic"), "Disconnected"),
            (.unsupported(deviceName: "Mic"), "Unsupported"),
            (.partial(deviceName: "All", muted: 0, live: 0, mixed: 0, unsupported: 1, failed: 0), "Partial"),
            (.error(message: "Failed"), "Error"),
        ]

        for (status, title) in values {
            XCTAssertEqual(status.statusOverlayTitle, title)
        }
    }

    @MainActor
    func testPanelUsesNonactivatingFloatingSpaceConfiguration() {
        let panel = StatusOverlayPanelFactory.makePanel()

        XCTAssertTrue(panel.styleMask.contains(.borderless))
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertEqual(panel.level, .floating)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(panel.collectionBehavior.contains(.ignoresCycle))
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertTrue(panel.hasShadow)
    }
}
