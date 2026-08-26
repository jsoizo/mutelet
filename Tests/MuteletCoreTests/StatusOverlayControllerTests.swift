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

    @MainActor
    func testCoordinatorObservationUsesPublishedBusyValues() async {
        let audio = MultiDeviceAudioController(
            states: ["built-in": .live],
            defaultUID: "built-in"
        )
        let coordinator = MuteCoordinator(
            audioController: audio,
            receiptStore: InMemoryReceiptStore(),
            maintenanceSleep: { _ in }
        )
        await coordinator.start()

        var observedStates: [StatusOverlayCoordinatorState] = []
        let observation = StatusOverlayCoordinatorObservation.observe(coordinator) {
            observedStates.append($0)
        }
        await audio.suspendNextMute(uid: "built-in")

        let transition = coordinator.selectMode(.pushToTalk)
        for _ in 0..<200 {
            if await audio.isMuteSuspended() { break }
            try? await Task.sleep(for: .milliseconds(5))
        }

        let muteSuspended = await audio.isMuteSuspended()
        XCTAssertTrue(muteSuspended)
        XCTAssertEqual(observedStates.last?.isBusy, true)

        await audio.resumeMute()
        await transition?.value

        XCTAssertEqual(observedStates.last?.isBusy, false)
        withExtendedLifetime(observation) {}
        await coordinator.stop()
    }

    func testHotKeyHUDIsPresentedForEveryPressAndForPushToTalkReleasesOnly() {
        let edgeDisabled = ScreenEdgeIndicatorPreferences()
        let live = MuteStatus.live(deviceName: "Mic")
        let muted = MuteStatus.muted(deviceName: "Mic")

        XCTAssertEqual(
            HotKeyHUDPresentation.feedback(
                event: .pressed, mode: .toggle, status: muted, screenEdge: edgeDisabled
            ),
            .hud
        )
        XCTAssertEqual(
            HotKeyHUDPresentation.feedback(
                event: .pressed, mode: .pushToTalk, status: live, screenEdge: edgeDisabled
            ),
            .hud
        )
        XCTAssertEqual(
            HotKeyHUDPresentation.feedback(
                event: .released, mode: .pushToTalk, status: muted, screenEdge: edgeDisabled
            ),
            .hud
        )
        XCTAssertEqual(
            HotKeyHUDPresentation.feedback(
                event: .released, mode: .toggle, status: muted, screenEdge: edgeDisabled
            ),
            .none
        )
    }

    func testScreenEdgeReplacesTheHotKeyHUDInPushToTalkOnly() {
        let edgeEnabled = ScreenEdgeIndicatorPreferences(isEnabled: true)
        let live = MuteStatus.live(deviceName: "Mic")
        let muted = MuteStatus.muted(deviceName: "Mic")

        XCTAssertEqual(
            HotKeyHUDPresentation.feedback(
                event: .pressed, mode: .pushToTalk, status: live, screenEdge: edgeEnabled
            ),
            .screenEdge
        )
        XCTAssertEqual(
            HotKeyHUDPresentation.feedback(
                event: .released, mode: .pushToTalk, status: muted, screenEdge: edgeEnabled
            ),
            .screenEdge
        )
        XCTAssertEqual(
            HotKeyHUDPresentation.feedback(
                event: .pressed, mode: .toggle, status: muted, screenEdge: edgeEnabled
            ),
            .hud
        )
    }

    func testHUDStillReportsResultsTheScreenEdgeCannotExpress() {
        let edgeEnabled = ScreenEdgeIndicatorPreferences(
            isEnabled: true,
            showsIdleOutline: true
        )

        for status in [
            MuteStatus.unavailable,
            .disconnected(deviceName: "Mic"),
            .loading,
        ] {
            XCTAssertEqual(
                HotKeyHUDPresentation.feedback(
                    event: .pressed,
                    mode: .pushToTalk,
                    status: status,
                    screenEdge: edgeEnabled
                ),
                .hud
            )
        }
    }

    func testScreenEdgeAnnouncementsFollowStatusChangesAndNotTheFirstStatus() {
        var gate = ScreenEdgeAnnouncementGate()
        let muted = MuteStatus.muted(deviceName: "Mic")
        let live = MuteStatus.live(deviceName: "Mic")

        XCTAssertFalse(gate.announces(status: muted, isScreenEdgeActive: true))
        XCTAssertTrue(gate.announces(status: live, isScreenEdgeActive: true))
        XCTAssertFalse(gate.announces(status: live, isScreenEdgeActive: true))
        XCTAssertTrue(gate.announces(status: muted, isScreenEdgeActive: true))
    }

    func testScreenEdgeAnnouncementsRestartAfterTheEdgeStopsReporting() {
        var gate = ScreenEdgeAnnouncementGate()
        let muted = MuteStatus.muted(deviceName: "Mic")
        let live = MuteStatus.live(deviceName: "Mic")

        XCTAssertFalse(gate.announces(status: muted, isScreenEdgeActive: true))
        XCTAssertFalse(gate.announces(status: live, isScreenEdgeActive: false))
        // Re-entering Push to Talk starts from a fresh baseline instead of announcing the
        // state the edge is simply showing.
        XCTAssertFalse(gate.announces(status: live, isScreenEdgeActive: true))
        XCTAssertTrue(gate.announces(status: muted, isScreenEdgeActive: true))
    }

    func testTheGateDropsAMaintenanceEchoThatRepeatsARecordedStatus() {
        // This is the contract the screen edge leans on: announcing a settled status also
        // records it, so the app's own Core Audio write coming back as .maintained cannot
        // show a HUD for what the edge already shows.
        let status = MuteStatus.live(deviceName: "Mic")
        let echo = AutomaticMuteMaintenanceFeedback.maintained(sequence: 1, status: status)
        var gate = HUDPresentationGate()

        gate.recordPresentation(
            signature: HUDContentSignature.signature(for: status),
            at: 100
        )

        XCTAssertFalse(
            gate.allowsPresentation(
                signature: HUDContentSignature.signature(for: echo),
                at: 100.05
            )
        )
        XCTAssertTrue(
            gate.allowsPresentation(
                signature: HUDContentSignature.signature(for: echo),
                at: 102
            )
        )
        XCTAssertTrue(
            gate.allowsPresentation(
                signature: HUDContentSignature.signature(
                    for: .restorationFailed(
                        sequence: 2,
                        currentStatus: status,
                        devices: [RestorationWarningItem(deviceUID: "usb", deviceName: "USB")]
                    )
                ),
                at: 100.05
            )
        )
    }

    func testMaintainedFeedbackSharesTheSignatureOfItsStatus() {
        let status = MuteStatus.muted(deviceName: "Built-in Microphone")

        XCTAssertEqual(
            HUDContentSignature.signature(for: .maintained(sequence: 1, status: status)),
            HUDContentSignature.signature(for: status)
        )
    }

    func testRestorationFailureSignatureIgnoresDeviceOrder() {
        func signature(_ deviceUIDs: [String]) -> String {
            HUDContentSignature.signature(
                for: .restorationFailed(
                    sequence: 1,
                    currentStatus: .muted(deviceName: "Built-in Microphone"),
                    devices: deviceUIDs.map {
                        RestorationWarningItem(deviceUID: $0, deviceName: $0)
                    }
                )
            )
        }

        XCTAssertEqual(signature(["usb", "built-in"]), signature(["built-in", "usb"]))
        XCTAssertNotEqual(signature(["usb"]), signature(["built-in"]))
    }

    func testRepeatedHUDContentIsDroppedOnlyWithinCoalescingWindow() {
        var gate = HUDPresentationGate(coalescingInterval: 2)
        let signature = HUDContentSignature.signature(
            for: .muted(deviceName: "Built-in Microphone")
        )

        XCTAssertTrue(gate.allowsPresentation(signature: signature, at: 10))
        gate.recordPresentation(signature: signature, at: 10)
        XCTAssertFalse(gate.allowsPresentation(signature: signature, at: 11.999))
        XCTAssertTrue(gate.allowsPresentation(signature: signature, at: 12))
    }

    func testMaintainedFeedbackForAnotherDeviceIsPresentedWithinCoalescingWindow() {
        var gate = HUDPresentationGate(coalescingInterval: 2)
        gate.recordPresentation(
            signature: HUDContentSignature.signature(
                for: .muted(deviceName: "Built-in Microphone")
            ),
            at: 10
        )

        XCTAssertFalse(
            gate.allowsPresentation(
                signature: HUDContentSignature.signature(
                    for: .maintained(
                        sequence: 1,
                        status: .muted(deviceName: "Built-in Microphone")
                    )
                ),
                at: 10.3
            )
        )
        XCTAssertTrue(
            gate.allowsPresentation(
                signature: HUDContentSignature.signature(
                    for: .maintained(sequence: 2, status: .muted(deviceName: "Headset"))
                ),
                at: 10.3
            )
        )
    }

    func testRepeatedRestorationFailureIsDroppedWithinCoalescingWindow() {
        var gate = HUDPresentationGate(coalescingInterval: 2)
        let failure = AutomaticMuteMaintenanceFeedback.restorationFailed(
            sequence: 1,
            currentStatus: .muted(deviceName: "Built-in Microphone"),
            devices: [RestorationWarningItem(deviceUID: "usb", deviceName: "USB Microphone")]
        )
        let signature = HUDContentSignature.signature(for: failure)

        XCTAssertTrue(gate.allowsPresentation(signature: signature, at: 10))
        gate.recordPresentation(signature: signature, at: 10)
        XCTAssertFalse(gate.allowsPresentation(signature: signature, at: 10.1))
        XCTAssertTrue(
            gate.allowsPresentation(
                signature: HUDContentSignature.signature(
                    for: .restorationFailed(
                        sequence: 2,
                        currentStatus: .muted(deviceName: "Built-in Microphone"),
                        devices: [
                            RestorationWarningItem(deviceUID: "usb", deviceName: "USB Microphone"),
                            RestorationWarningItem(deviceUID: "hdmi", deviceName: "HDMI Input"),
                        ]
                    )
                ),
                at: 10.1
            )
        )
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
        XCTAssertTrue(
            StatusOverlayInteraction.isActionable(
                preferences: enabled,
                mode: .toggle,
                status: .disconnected(deviceName: "Mic"),
                isBusy: false,
                isClickInFlight: false,
                hasToggleMuteIntent: true
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
                status: .externallySilenced(deviceName: "Mic"),
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
            (.externallySilenced(deviceName: "Mic"), "No control"),
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
