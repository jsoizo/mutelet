import Combine
import Foundation

@MainActor
public final class MuteCoordinator: ObservableObject {
    @Published public private(set) var status: MuteStatus = .loading
    @Published public private(set) var isBusy = false
    @Published public private(set) var mode: MuteMode = .toggle

    private let audioController: any AudioDeviceControlling
    private let receiptStore: any AudioMutationReceiptStoring
    private var eventTask: Task<Void, Never>?
    private var started = false
    private var isHotKeyPressed = false
    private var operationInProgress = false
    private var operationWaiters: [CheckedContinuation<Void, Never>] = []

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
        if mode == .pushToTalk {
            await muteIfNeeded()
        }

        do {
            let events = try await audioController.events()
            eventTask = Task { [weak self] in
                for await _ in events {
                    guard !Task.isCancelled else { break }
                    await self?.handleAudioEvent()
                }
            }
        } catch {
            status = .error(message: String(describing: error))
        }
    }

    public func stop() async {
        isHotKeyPressed = false
        if mode == .pushToTalk {
            await muteIfNeeded()
        }
        eventTask?.cancel()
        eventTask = nil
        started = false
    }

    public func setMode(_ newMode: MuteMode) async {
        let transition = selectMode(newMode)
        await transition?.value
    }

    @discardableResult
    public func selectMode(_ newMode: MuteMode) -> Task<Void, Never>? {
        guard newMode != mode else { return nil }

        let previousMode = mode
        isHotKeyPressed = false
        mode = newMode
        guard previousMode == .pushToTalk || newMode == .pushToTalk else { return nil }

        isBusy = true
        return Task { [weak self] in
            await self?.muteIfNeeded()
        }
    }

    public func handleHotKey(_ event: GlobalHotKeyEvent) async {
        switch event {
        case .pressed:
            guard !isHotKeyPressed else { return }
            isHotKeyPressed = true
            switch mode {
            case .toggle:
                await toggle()
            case .pushToTalk:
                await unmuteIfNeeded()
            }
        case .released:
            guard isHotKeyPressed else { return }
            isHotKeyPressed = false
            if mode == .pushToTalk {
                await muteIfNeeded()
            }
        }
    }

    public func toggle() async {
        guard mode == .toggle else { return }
        guard !isBusy, status.canToggle else { return }
        switch status {
        case .muted:
            await unmuteIfNeeded()
        case .live, .mixed:
            await muteIfNeeded()
        case .loading, .unavailable, .unsupported, .error:
            return
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

    private func handleAudioEvent() async {
        await refresh()
        if mode == .pushToTalk, !isHotKeyPressed {
            await muteIfNeeded()
        }
    }

    private func muteIfNeeded() async {
        await acquireOperation()
        defer { releaseOperation() }
        guard status.canToggle, !status.isMuted else { return }

        do {
            guard let device = try await audioController.defaultInputDevice() else {
                status = .unavailable
                return
            }
            let existingReceipt = await receiptStore.receipt(deviceUID: device.uid)
            let receipt = try await audioController.mute(
                deviceUID: device.uid,
                preserving: existingReceipt
            )
            try await receiptStore.save(receipt)
            await refresh()
        } catch {
            status = .error(message: String(describing: error))
        }
    }

    private func unmuteIfNeeded() async {
        await acquireOperation()
        defer { releaseOperation() }
        guard status.isMuted else { return }

        do {
            guard let device = try await audioController.defaultInputDevice() else {
                status = .unavailable
                return
            }
            let receipt = await receiptStore.receipt(deviceUID: device.uid)
            try await audioController.unmute(
                deviceUID: device.uid,
                restoring: receipt
            )
            if receipt != nil {
                try await receiptStore.removeReceipt(deviceUID: device.uid)
            }
            await refresh()
        } catch {
            status = .error(message: String(describing: error))
        }
    }

    private func acquireOperation() async {
        if !operationInProgress {
            operationInProgress = true
            isBusy = true
            return
        }

        await withCheckedContinuation { continuation in
            operationWaiters.append(continuation)
        }
    }

    private func releaseOperation() {
        guard !operationWaiters.isEmpty else {
            operationInProgress = false
            isBusy = false
            return
        }

        let next = operationWaiters.removeFirst()
        next.resume()
    }
}
