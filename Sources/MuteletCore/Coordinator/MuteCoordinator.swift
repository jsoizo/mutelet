import Combine
import CoreAudio
import Foundation

@MainActor
public final class MuteCoordinator: ObservableObject {
    private static let audioEventCoalescingDelay = Duration.milliseconds(10)

    @Published public private(set) var status: MuteStatus = .loading
    @Published public private(set) var isBusy = false
    @Published public private(set) var mode: MuteMode = .toggle
    @Published public private(set) var target: AudioTargetSelection = .systemDefault
    @Published public private(set) var availableDevices: [AudioDeviceDescriptor] = []
    @Published public private(set) var targetWarning: String?

    private let audioController: any AudioDeviceControlling
    private let receiptStore: any AudioMutationReceiptStoring
    private var startupTask: Task<Void, Never>?
    private var startupID: UUID?
    private var eventTask: Task<Void, Never>?
    private var audioEventProcessingTask: Task<Void, Never>?
    private var audioEventProcessingID: UUID?
    private var audioEventGeneration: UInt64 = 0
    private var started = false
    private var isHotKeyPressed = false
    private var shouldUnmuteTargets = false
    private var keepAllInputsMuted = false
    private var operationInProgress = false
    private var operationWaiters: [CheckedContinuation<Void, Never>] = []
    private var pendingInventoryRefresh = false
    private var pendingControlObjectIDs: Set<AudioObjectID> = []

    public init(
        audioController: any AudioDeviceControlling,
        receiptStore: any AudioMutationReceiptStoring
    ) {
        self.audioController = audioController
        self.receiptStore = receiptStore
    }

    public func configure(
        mode: MuteMode,
        target: AudioTargetSelection
    ) {
        guard !started else { return }
        self.mode = mode
        self.target = target
    }

    public func start() async {
        guard !started else { return }
        started = true
        audioEventGeneration &+= 1
        let generation = audioEventGeneration
        let startupID = UUID()
        self.startupID = startupID
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performStart(id: startupID, generation: generation)
        }
        startupTask = task
        await task.value
        clearStartup(id: startupID, generation: generation)
    }

    private func performStart(id: UUID, generation: UInt64) async {
        do {
            let events = try await audioController.events()
            guard !Task.isCancelled,
                  isCurrentStartup(id: id, generation: generation) else {
                return
            }
            eventTask = Task { [weak self] in
                for await event in events {
                    guard !Task.isCancelled else { break }
                    guard let self,
                          self.started,
                          self.audioEventGeneration == generation else {
                        break
                    }
                    self.enqueueAudioEvent(event)
                }
            }
            await refresh()
            guard !Task.isCancelled,
                  isCurrentStartup(id: id, generation: generation) else {
                return
            }
            if mode == .pushToTalk {
                await muteIfNeeded(forceForSafety: true)
            }
        } catch {
            guard !Task.isCancelled,
                  isCurrentStartup(id: id, generation: generation) else {
                return
            }
            status = .error(message: userFacingErrorMessage(for: error))
        }
    }

    public func stop() async {
        isHotKeyPressed = false
        audioEventGeneration &+= 1
        let currentStartupTask = startupTask
        startupTask = nil
        startupID = nil
        currentStartupTask?.cancel()
        let currentEventTask = eventTask
        eventTask = nil
        currentEventTask?.cancel()
        let currentProcessingTask = audioEventProcessingTask
        audioEventProcessingTask = nil
        audioEventProcessingID = nil
        currentProcessingTask?.cancel()
        pendingInventoryRefresh = false
        pendingControlObjectIDs.removeAll()

        await currentEventTask?.value
        await currentProcessingTask?.value
        await currentStartupTask?.value
        if mode == .pushToTalk {
            await muteIfNeeded(forceForSafety: true)
        }
        started = false
    }

    private func isCurrentStartup(id: UUID, generation: UInt64) -> Bool {
        started && audioEventGeneration == generation && startupID == id
    }

    private func clearStartup(id: UUID, generation: UInt64) {
        guard audioEventGeneration == generation,
              startupID == id else {
            return
        }
        startupTask = nil
        startupID = nil
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
            await self?.muteIfNeeded(forceForSafety: true)
        }
    }

    public func selectTarget(_ newTarget: AudioTargetSelection) async {
        guard newTarget.id != target.id else { return }

        let previousDevices = (try? await resolvedTargetDevices()) ?? []
        if mode == .pushToTalk {
            guard await muteIfNeeded(forceForSafety: true) else { return }
            isHotKeyPressed = false
        } else {
            isHotKeyPressed = false
            guard await unmuteIfNeeded(onlyWithReceipts: true) else { return }
        }

        target = newTarget
        keepAllInputsMuted = false
        await refresh()

        if mode == .pushToTalk {
            await muteIfNeeded(forceForSafety: true)
            let currentUIDs = Set(
                ((try? await resolvedTargetDevices()) ?? []).map(\.uid)
            )
            _ = await restoreManagedDevices(
                previousDevices.filter { !currentUIDs.contains($0.uid) }
            )
        }
    }

    public func handleHotKey(_ event: GlobalHotKeyEvent) async {
        let measurement = CoreAudioDiagnostics.measure("handleHotKey.\(event.rawValue)")
        defer { measurement.finish() }

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
                await muteIfNeeded(forceForSafety: true)
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

    @discardableResult
    public func cancelActiveHotKeyGesture() async -> Bool {
        guard isHotKeyPressed else { return true }
        if mode == .pushToTalk {
            guard await muteIfNeeded(forceForSafety: true) else { return false }
        }
        isHotKeyPressed = false
        return true
    }

    private func enqueueAudioEvent(_ event: AudioHardwareEvent) {
        switch event.kind {
        case .deviceListChanged, .defaultInputChanged:
            pendingInventoryRefresh = true
        case .controlValueChanged:
            guard controlEventAffectsCurrentTarget(objectID: event.objectID) else { return }
            pendingControlObjectIDs.insert(event.objectID)
        }
        scheduleAudioEventProcessing()
    }

    private func scheduleAudioEventProcessing() {
        guard started,
              audioEventProcessingTask == nil,
              pendingInventoryRefresh || !pendingControlObjectIDs.isEmpty else {
            return
        }
        let generation = audioEventGeneration
        let processingID = UUID()
        audioEventProcessingID = processingID
        audioEventProcessingTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.audioEventCoalescingDelay)
            } catch {
                self?.clearAudioEventProcessing(
                    id: processingID,
                    generation: generation
                )
                return
            }
            await self?.processPendingAudioEvents(
                id: processingID,
                generation: generation
            )
        }
    }

    private func processPendingAudioEvents(id: UUID, generation: UInt64) async {
        guard isCurrentAudioEventProcessing(id: id, generation: generation) else { return }
        guard !operationInProgress else {
            clearAudioEventProcessing(id: id, generation: generation)
            return
        }
        guard pendingInventoryRefresh || !pendingControlObjectIDs.isEmpty else {
            clearAudioEventProcessing(id: id, generation: generation)
            return
        }

        pendingInventoryRefresh = false
        pendingControlObjectIDs.removeAll()
        await refresh()

        guard !Task.isCancelled,
              isCurrentAudioEventProcessing(id: id, generation: generation) else {
            clearAudioEventProcessing(id: id, generation: generation)
            return
        }

        if mode == .pushToTalk {
            if !isHotKeyPressed, !shouldUnmuteTargets {
                await muteIfNeeded(forceForSafety: true)
            }
        } else if target == .allInputs, keepAllInputsMuted, !shouldUnmuteTargets {
            await muteIfNeeded()
        }

        if clearAudioEventProcessing(id: id, generation: generation) {
            scheduleAudioEventProcessing()
        }
    }

    private func isCurrentAudioEventProcessing(id: UUID, generation: UInt64) -> Bool {
        started
            && audioEventGeneration == generation
            && audioEventProcessingID == id
    }

    @discardableResult
    private func clearAudioEventProcessing(id: UUID, generation: UInt64) -> Bool {
        guard audioEventGeneration == generation,
              audioEventProcessingID == id else {
            return false
        }
        audioEventProcessingTask = nil
        audioEventProcessingID = nil
        return true
    }

    private func controlEventAffectsCurrentTarget(objectID: AudioObjectID) -> Bool {
        guard let device = availableDevices.first(where: { $0.objectID == objectID }) else {
            return false
        }
        return switch target {
        case .systemDefault:
            device.isDefaultInput
        case let .device(uid, _):
            device.uid == uid
        case .allInputs:
            true
        }
    }

    @discardableResult
    private func muteIfNeeded(forceForSafety: Bool = false) async -> Bool {
        await acquireOperation()
        defer { releaseOperation() }
        if !forceForSafety {
            guard status.canToggle, !shouldUnmuteTargets else { return true }
        }

        do {
            let devices = try await resolvedTargetDevices()
            guard !devices.isEmpty else {
                await refreshStatus()
                return false
            }

            var failures = 0
            var firstError: Error?
            for device in devices {
                do {
                    guard device.capabilities.isSupported else {
                        throw CoreAudioError.unsupportedDevice(uid: device.uid)
                    }
                    var receipt = await receiptStore.receipt(deviceUID: device.uid)
                    if receipt == nil {
                        let snapshot = try await audioController.snapshot(deviceUID: device.uid)
                        let preparedReceipt = AudioMutationReceipt(
                            deviceUID: device.uid,
                            originalValues: snapshot.values
                        )
                        try await receiptStore.save(preparedReceipt)
                        receipt = preparedReceipt
                    }
                    _ = try await audioController.mute(
                        deviceUID: device.uid,
                        preserving: receipt
                    )
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
                status = .error(message: userFacingErrorMessage(for: firstError))
            }
            return failures == 0
        } catch {
            status = .error(message: userFacingErrorMessage(for: error))
            return false
        }
    }

    @discardableResult
    private func unmuteIfNeeded(onlyWithReceipts: Bool = false) async -> Bool {
        await acquireOperation()
        defer { releaseOperation() }
        guard onlyWithReceipts || shouldUnmuteTargets else { return true }

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
                    if onlyWithReceipts, receipt == nil {
                        continue
                    }
                    try await audioController.unmute(
                        deviceUID: device.uid,
                        restoring: receipt
                    )
                    if let receipt {
                        let restored = try await audioController.snapshot(deviceUID: device.uid)
                        guard Self.snapshot(restored, matches: receipt) else {
                            throw CoreAudioError.incompleteRestoration(uid: device.uid)
                        }
                        try await receiptStore.removeReceipt(deviceUID: device.uid)
                    }
                } catch {
                    failures += 1
                    firstError = firstError ?? error
                }
            }

            await refreshStatus(additionalFailures: failures)
            if failures > 0, target != .allInputs, let firstError {
                status = .error(message: userFacingErrorMessage(for: firstError))
            }
            return failures == 0
        } catch {
            status = .error(message: userFacingErrorMessage(for: error))
            return false
        }
    }

    private func refreshStatus(additionalFailures: Int = 0) async {
        let measurement = CoreAudioDiagnostics.measure("refreshStatus")
        defer { measurement.finish() }

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
                ? NSLocalizedString(
                    "Volume-only mute may not guarantee complete silence.",
                    comment: "Volume-only input warning"
                )
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
                status = .error(
                    message: NSLocalizedString(
                        "Reading the selected input device failed",
                        comment: "Selected microphone read error"
                    )
                )
            }
        } catch {
            availableDevices = []
            targetWarning = nil
            shouldUnmuteTargets = false
            status = .error(message: userFacingErrorMessage(for: error))
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
                deviceName: AudioTargetSelection.allInputs.title,
                muted: muted,
                live: live,
                mixed: mixed,
                unsupported: unsupported,
                failed: failures
            )
        } else if !snapshots.isEmpty, muted == snapshots.count {
            status = .muted(deviceName: AudioTargetSelection.allInputs.title)
        } else if !snapshots.isEmpty, live == snapshots.count {
            status = .live(deviceName: AudioTargetSelection.allInputs.title)
        } else if snapshots.isEmpty {
            status = .unavailable
        } else {
            status = .mixed(deviceName: AudioTargetSelection.allInputs.title)
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
            scheduleAudioEventProcessing()
            return
        }

        let next = operationWaiters.removeFirst()
        next.resume()
    }

    private static func snapshot(
        _ snapshot: AudioDeviceSnapshot,
        matches receipt: AudioMutationReceipt
    ) -> Bool {
        let currentValues = Dictionary(
            uniqueKeysWithValues: snapshot.values.map { ($0.control, $0.value) }
        )
        return receipt.originalValues.allSatisfy { saved in
            guard let current = currentValues[saved.control] else { return false }
            return abs(current - saved.value) <= 0.0001
        }
    }

    private func userFacingErrorMessage(for error: Error) -> String {
        NSLog("Mutelet microphone error: %@", String(describing: error))
        return NSLocalizedString(
            "The microphone could not be controlled.",
            comment: "Generic microphone control error"
        )
    }

    @discardableResult
    private func restoreManagedDevices(
        _ devices: [AudioDeviceDescriptor]
    ) async -> Bool {
        guard !devices.isEmpty else { return true }
        await acquireOperation()
        defer { releaseOperation() }

        var firstError: Error?
        for device in devices {
            guard let receipt = await receiptStore.receipt(deviceUID: device.uid) else {
                continue
            }
            do {
                try await audioController.unmute(
                    deviceUID: device.uid,
                    restoring: receipt
                )
                let restored = try await audioController.snapshot(deviceUID: device.uid)
                guard Self.snapshot(restored, matches: receipt) else {
                    throw CoreAudioError.incompleteRestoration(uid: device.uid)
                }
                try await receiptStore.removeReceipt(deviceUID: device.uid)
            } catch {
                firstError = firstError ?? error
            }
        }

        await refreshStatus()
        if let firstError {
            status = .error(message: userFacingErrorMessage(for: firstError))
            return false
        }
        return true
    }
}
