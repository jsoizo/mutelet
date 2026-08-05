import Combine
import Foundation

@MainActor
public final class MuteCoordinator: ObservableObject {
    @Published public private(set) var status: MuteStatus = .loading
    @Published public private(set) var isBusy = false

    private let audioController: any AudioDeviceControlling
    private let receiptStore: any AudioMutationReceiptStoring
    private var eventTask: Task<Void, Never>?
    private var started = false

    public init(
        audioController: any AudioDeviceControlling,
        receiptStore: any AudioMutationReceiptStoring
    ) {
        self.audioController = audioController
        self.receiptStore = receiptStore
    }

    public func start() async {
        guard !started else { return }
        started = true
        await refresh()

        do {
            let events = try await audioController.events()
            eventTask = Task { [weak self] in
                for await _ in events {
                    guard !Task.isCancelled else { break }
                    await self?.refresh()
                }
            }
        } catch {
            status = .error(message: String(describing: error))
        }
    }

    public func stop() {
        eventTask?.cancel()
        eventTask = nil
        started = false
    }

    public func toggle() async {
        guard !isBusy, status.canToggle else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            guard let device = try await audioController.defaultInputDevice() else {
                status = .unavailable
                return
            }
            switch status {
            case .muted:
                let receipt = await receiptStore.receipt(deviceUID: device.uid)
                try await audioController.unmute(
                    deviceUID: device.uid,
                    restoring: receipt
                )
                if receipt != nil {
                    try await receiptStore.removeReceipt(deviceUID: device.uid)
                }
            case .live, .mixed:
                let existingReceipt = await receiptStore.receipt(deviceUID: device.uid)
                let receipt = try await audioController.mute(
                    deviceUID: device.uid,
                    preserving: existingReceipt
                )
                try await receiptStore.save(receipt)
            case .loading, .unavailable, .unsupported, .error:
                return
            }
            await refresh()
        } catch {
            status = .error(message: String(describing: error))
        }
    }

    public func refresh() async {
        do {
            guard let device = try await audioController.defaultInputDevice() else {
                status = .unavailable
                return
            }
            let snapshot = try await audioController.snapshot(deviceUID: device.uid)
            status = switch snapshot.muteState {
            case .live:
                .live(deviceName: device.name)
            case .muted:
                .muted(deviceName: device.name)
            case .mixed:
                .mixed(deviceName: device.name)
            case .unsupported:
                .unsupported(deviceName: device.name)
            }
        } catch {
            status = .error(message: String(describing: error))
        }
    }
}
