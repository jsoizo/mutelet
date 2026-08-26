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

enum HotKeyHUDPresentation {
    static func presents(event: GlobalHotKeyEvent, mode: MuteMode) -> Bool {
        // Toggle mode does not change state on release, so it has nothing to report.
        event == .pressed || mode == .pushToTalk
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
