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

struct MaintenanceAnnouncementGate {
    private let coalescingInterval: TimeInterval
    private var lastSignature: String?
    private var lastAnnouncementTime: TimeInterval = -.infinity

    init(coalescingInterval: TimeInterval = 2) {
        self.coalescingInterval = coalescingInterval
    }

    mutating func shouldAnnounce(
        signature: String,
        at time: TimeInterval
    ) -> Bool {
        guard signature != lastSignature
                || time - lastAnnouncementTime >= coalescingInterval else {
            return false
        }
        lastSignature = signature
        lastAnnouncementTime = time
        return true
    }
}
