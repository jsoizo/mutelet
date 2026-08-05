import Combine
import Foundation

@MainActor
public final class MuteCoordinator: ObservableObject {
    @Published public private(set) var status: MuteStatus = .loading
    @Published public private(set) var isBusy = false
    @Published public private(set) var mode: MuteMode = .toggle
    @Published public private(set) var target: AudioTargetSelection = .systemDefault
    @Published public private(set) var availableDevices: [AudioDeviceDescriptor] = []
    @Published public private(set) var targetWarning: String?

    private let audioController: any AudioDeviceControlling
    private let receiptStore: any AudioMutationReceiptStoring
    private var eventTask: Task<Void, Never>?
    private var started = false
    private var isHotKeyPressed = false
    private var shouldUnmuteTargets = false
    private var keepAllInputsMuted = false
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

    public func selectTarget(_ newTarget: AudioTargetSelection) async {
        guard newTarget.id != target.id else { return }

        isHotKeyPressed = false
        if mode == .pushToTalk {
            await muteIfNeeded()
        }

        target = newTarget
        keepAllInputsMuted = false
        await refresh()

        if mode == .pushToTalk {
            await muteIfNeeded()
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
        if shouldUnmuteTargets {
            await unmuteIfNeeded()
        } else {
            await muteIfNeeded()
        }
    }

    public func refresh() async {
        await refreshStatus()
    }

    private func handleAudioEvent() async {
        await refresh()

        if mode == .pushToTalk {
            if !isHotKeyPressed {
                await muteIfNeeded()
            }
        } else if target == .allInputs, keepAllInputsMuted, !shouldUnmuteTargets {
            await muteIfNeeded()
        }
    }

    private func muteIfNeeded() async {
        await acquireOperation()
        defer { releaseOperation() }
        guard status.canToggle, !shouldUnmuteTargets else { return }

        do {
            let devices = try await resolvedTargetDevices()
            guard !devices.isEmpty else {
                await refreshStatus()
                return
            }

            var failures = 0
            var firstError: Error?
            for device in devices {
                do {
                    let existingReceipt = await receiptStore.receipt(deviceUID: device.uid)
                    let receipt = try await audioController.mute(
                        deviceUID: device.uid,
                        preserving: existingReceipt
                    )
                    try await receiptStore.save(receipt)
                } catch {
                    failures += 1
                    firstError = firstError ?? error
                }
            }

            if target == .allInputs {
                keepAllInputsMuted = true
            }
            await refreshStatus(additionalFailures: failures)
            if failures > 0, target != .allInputs, let firstError {
                status = .error(message: String(describing: firstError))
            }
        } catch {
            status = .error(message: String(describing: error))
        }
    }

    private func unmuteIfNeeded() async {
        await acquireOperation()
        defer { releaseOperation() }
        guard shouldUnmuteTargets else { return }

        if target == .allInputs {
            keepAllInputsMuted = false
        }

        do {
            let devices = try await resolvedTargetDevices()
            var failures = 0
            var firstError: Error?
            for device in devices {
                do {
                    let receipt = await receiptStore.receipt(deviceUID: device.uid)
                    try await audioController.unmute(
                        deviceUID: device.uid,
                        restoring: receipt
                    )
                    if receipt != nil {
                        try await receiptStore.removeReceipt(deviceUID: device.uid)
                    }
                } catch {
                    failures += 1
                    firstError = firstError ?? error
                }
            }

            await refreshStatus(additionalFailures: failures)
            if failures > 0, target != .allInputs, let firstError {
                status = .error(message: String(describing: firstError))
            }
        } catch {
            status = .error(message: String(describing: error))
        }
    }

    private func refreshStatus(additionalFailures: Int = 0) async {
        do {
            let allDevices = try await audioController.inputDevices()
            availableDevices = allDevices
            if case let .device(uid, name) = target,
               let reconnectedDevice = allDevices.first(where: { $0.uid == uid }),
               reconnectedDevice.name != name {
                target = .device(uid: uid, name: reconnectedDevice.name)
            }
            let devices = try await resolvedTargetDevices(availableDevices: allDevices)

            guard !devices.isEmpty else {
                targetWarning = nil
                shouldUnmuteTargets = false
                status = switch target {
                case .systemDefault, .allInputs:
                    .unavailable
                case let .device(_, name):
                    .disconnected(deviceName: name)
                }
                return
            }

            let fallbackCount = devices.filter(\.capabilities.usesVolumeFallbackOnly).count
            targetWarning = fallbackCount > 0
                ? "Volume-only mute may not guarantee complete silence."
                : nil

            var snapshots: [AudioDeviceSnapshot] = []
            var readFailures = 0
            for device in devices {
                do {
                    snapshots.append(try await audioController.snapshot(deviceUID: device.uid))
                } catch {
                    readFailures += 1
                }
            }

            let operableSnapshots = snapshots.filter { $0.muteState != .unsupported }
            shouldUnmuteTargets = !operableSnapshots.isEmpty
                && operableSnapshots.allSatisfy { $0.muteState == .muted }

            if target == .allInputs {
                publishAggregateStatus(
                    snapshots: snapshots,
                    failures: max(readFailures, additionalFailures)
                )
            } else if let snapshot = snapshots.first {
                status = status(for: snapshot)
            } else {
                status = .error(message: "Reading the selected input device failed")
            }
        } catch {
            availableDevices = []
            targetWarning = nil
            shouldUnmuteTargets = false
            status = .error(message: String(describing: error))
        }
    }

    private func resolvedTargetDevices(
        availableDevices: [AudioDeviceDescriptor]? = nil
    ) async throws -> [AudioDeviceDescriptor] {
        let devices: [AudioDeviceDescriptor]
        if let availableDevices {
            devices = availableDevices
        } else {
            devices = try await audioController.inputDevices()
        }
        switch target {
        case .systemDefault:
            if let device = devices.first(where: \.isDefaultInput) {
                return [device]
            }
            if let device = try await audioController.defaultInputDevice() {
                return [device]
            }
            return []
        case let .device(uid, _):
            return devices.filter { $0.uid == uid }
        case .allInputs:
            return devices
        }
    }

    private func publishAggregateStatus(
        snapshots: [AudioDeviceSnapshot],
        failures: Int
    ) {
        let muted = snapshots.filter { $0.muteState == .muted }.count
        let live = snapshots.filter { $0.muteState == .live }.count
        let mixed = snapshots.filter { $0.muteState == .mixed }.count
        let unsupported = snapshots.filter { $0.muteState == .unsupported }.count

        if failures > 0 || unsupported > 0 {
            status = .partial(
                deviceName: "All Inputs",
                muted: muted,
                live: live,
                mixed: mixed,
                unsupported: unsupported,
                failed: failures
            )
        } else if !snapshots.isEmpty, muted == snapshots.count {
            status = .muted(deviceName: "All Inputs")
        } else if !snapshots.isEmpty, live == snapshots.count {
            status = .live(deviceName: "All Inputs")
        } else if snapshots.isEmpty {
            status = .unavailable
        } else {
            status = .mixed(deviceName: "All Inputs")
        }
    }

    private func status(for snapshot: AudioDeviceSnapshot) -> MuteStatus {
        switch snapshot.muteState {
        case .live:
            .live(deviceName: snapshot.device.name)
        case .muted:
            .muted(deviceName: snapshot.device.name)
        case .mixed:
            .mixed(deviceName: snapshot.device.name)
        case .unsupported:
            .unsupported(deviceName: snapshot.device.name)
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
