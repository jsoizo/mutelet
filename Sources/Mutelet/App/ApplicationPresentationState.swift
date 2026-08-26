import Combine
import Foundation
import MuteletCore

struct StatusOverlayCoordinatorState: Equatable {
    let status: MuteStatus
    let mode: MuteMode
    let isBusy: Bool
    let hasToggleMuteIntent: Bool
}

@MainActor
enum StatusOverlayCoordinatorObservation {
    static func observe(
        _ coordinator: MuteCoordinator,
        receive: @escaping (StatusOverlayCoordinatorState) -> Void
    ) -> AnyCancellable {
        Publishers.CombineLatest4(
            coordinator.$status,
            coordinator.$mode,
            coordinator.$isBusy,
            coordinator.$hasToggleMuteIntent
        )
        .map(StatusOverlayCoordinatorState.init)
        .sink(receiveValue: receive)
    }
}

enum HotKeyFeedback: Equatable {
    case none
    case hud
    // The screen edge reports this gesture. Nothing is reported here, because a release
    // returns before the remute settles and would report the state it just left.
    case screenEdge
}

enum HotKeyHUDPresentation {
    static func feedback(
        event: GlobalHotKeyEvent,
        mode: MuteMode,
        status: MuteStatus,
        screenEdge: ScreenEdgeIndicatorPreferences
    ) -> HotKeyFeedback {
        // Toggle mode does not change state on release, so it has nothing to report.
        guard event == .pressed || mode == .pushToTalk else { return .none }
        guard ScreenEdgeIndicatorPresentation.suppressesHotKeyHUD(
            mode: mode,
            preferences: screenEdge
        ), ScreenEdgeIndicatorPresentation.expressesGestureResult(status) else { return .hud }
        return .screenEdge
    }
}

// While the screen edge reports Push to Talk, VoiceOver follows the status the edge is
// showing rather than the gesture, so both describe the same confirmed state.
struct ScreenEdgeAnnouncementGate {
    private var announcedStatus: MuteStatus?

    mutating func announces(status: MuteStatus, isScreenEdgeActive: Bool) -> Bool {
        guard isScreenEdgeActive else {
            announcedStatus = nil
            return false
        }
        let previous = announcedStatus
        announcedStatus = status
        // The first status after the edge becomes active is the state it starts from,
        // not a change to announce.
        guard let previous else { return false }
        return previous != status
    }
}

enum HUDContentSignature {
    static func signature(for status: MuteStatus) -> String {
        "status:\(status.title)"
    }

    static func signature(for feedback: AutomaticMuteMaintenanceFeedback) -> String {
        switch feedback {
        case let .maintained(_, status):
            // Shares the plain status signature so an automatic remute cannot repeat
            // what a hot key or a mode change already showed.
            return signature(for: status)
        case let .restorationFailed(_, status, devices):
            let deviceUIDs = devices.map(\.deviceUID).sorted().joined(separator: ",")
            return "restoration:\(status.title):\(deviceUIDs)"
        }
    }
}

struct HUDPresentationGate {
    private let coalescingInterval: TimeInterval
    private var lastSignature: String?
    private var lastPresentationTime: TimeInterval = -.infinity

    init(coalescingInterval: TimeInterval = 2) {
        self.coalescingInterval = coalescingInterval
    }

    // Repeats of what the HUD already shows are dropped rather than delayed; delaying them
    // used to surface a state that had changed in the meantime.
    func allowsPresentation(signature: String, at time: TimeInterval) -> Bool {
        signature != lastSignature || time - lastPresentationTime >= coalescingInterval
    }

    mutating func recordPresentation(signature: String, at time: TimeInterval) {
        lastSignature = signature
        lastPresentationTime = time
    }
}
