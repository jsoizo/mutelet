import Combine
import CoreAudio
import Foundation

private func sleepForMuteMaintenance(_ duration: Duration) async throws {
    try await Task.sleep(for: duration)
}

@MainActor
public final class MuteCoordinator: ObservableObject {
    private static let audioEventCoalescingDelay = Duration.milliseconds(10)

    @Published public private(set) var status: MuteStatus = .loading
    @Published public private(set) var isBusy = false
    @Published public private(set) var mode: MuteMode = .toggle
    @Published public private(set) var target: AudioTargetSelection = .systemDefault
    @Published public private(set) var availableDevices: [AudioDeviceDescriptor] = []
    @Published public private(set) var targetWarning: String?
    @Published public private(set) var restorationWarnings: [RestorationWarningItem] = []
    @Published public private(set) var maintenanceFeedback: AutomaticMuteMaintenanceFeedback?
    @Published public private(set) var hasToggleMuteIntent = false

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
    private var maintainsMuteOnInputChange = true
    private var activeTargetUIDs: Set<String> = []
    private var sessionManagedUIDs: Set<String> = []
    private var pendingRestoreNames: [String: String] = [:]
    private var lastKnownDeviceNames: [String: String] = [:]
    private var maintenanceFailureNames: [String: String] = [:]
    private var maintenanceGeneration: UInt64 = 0
    private var maintenanceFeedbackSequence: UInt64 = 0
    private var targetSelectionGeneration: UInt64 = 0
    private var maintenancePreferenceGeneration: UInt64 = 0
    private var maintenanceTasks: [UUID: Task<Void, Never>] = [:]
    private var completedMaintenanceTaskIDs: Set<UUID> = []
    private let maintenanceSleep: @Sendable (Duration) async throws -> Void
    private var operationInProgress = false
    private var operationWaiters: [CheckedContinuation<Void, Never>] = []
    private var pendingInventoryRefresh = false
    private var pendingControlObjectIDs: Set<AudioObjectID> = []

    private struct MaintenanceAttemptResult {
        let needsRetry: Bool
        let currentTargetFailures: Int
    }

    private struct MuteAttemptResult {
        let succeeded: Bool
        let confirmedUIDs: Set<String>
        let failureCount: Int

        static let cancelled = MuteAttemptResult(
            succeeded: false,
            confirmedUIDs: [],
            failureCount: 0
        )
    }

    public var canToggle: Bool {
        mode == .toggle && (hasToggleMuteIntent || status.canToggle)
    }

    public var toggleActionIsUnmute: Bool {
        hasToggleMuteIntent || status.isMuted
    }

    public init(
        audioController: any AudioDeviceControlling,
        receiptStore: any AudioMutationReceiptStoring
    ) {
        self.audioController = audioController
        self.receiptStore = receiptStore
        self.maintenanceSleep = sleepForMuteMaintenance
    }

    public init(
        audioController: any AudioDeviceControlling,
        receiptStore: any AudioMutationReceiptStoring,
        maintenanceSleep: @escaping @Sendable (Duration) async throws -> Void
    ) {
        self.audioController = audioController
        self.receiptStore = receiptStore
        self.maintenanceSleep = maintenanceSleep
    }

    public func configure(
        mode: MuteMode,
        target: AudioTargetSelection,
        maintainsMuteOnInputChange: Bool = true
    ) {
        guard !started else { return }
        self.mode = mode
        self.target = target
        self.maintainsMuteOnInputChange = maintainsMuteOnInputChange
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
            } else if hasToggleMuteIntent, maintainsMuteOnInputChange {
                await restartMaintenance(emitFeedback: true).value
            } else if !pendingRestoreNames.isEmpty {
                await restartMaintenance(emitFeedback: true).value
            } else {
                activeTargetUIDs = Set(
                    ((try? await resolvedTargetDevices()) ?? []).map(\.uid)
                )
            }
        } catch {
            guard !Task.isCancelled,
                  isCurrentStartup(id: id, generation: generation) else {
                return
            }
            status = .error(message: userFacingErrorMessage(for: error))
        }
    }

    public func suspend() async {
        isHotKeyPressed = false
        audioEventGeneration &+= 1
        maintenanceGeneration &+= 1
        let currentMaintenanceTasks = Array(maintenanceTasks.values)
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
        for task in currentMaintenanceTasks {
            await task.value
        }
        maintenanceTasks.removeAll()
        completedMaintenanceTaskIDs.removeAll()
        if mode == .pushToTalk {
            await muteIfNeeded(forceForSafety: true)
        }
        started = false
    }

    public func resume() async {
        await start()
    }

    public func shutdown() async {
        await suspend()
        hasToggleMuteIntent = false
        activeTargetUIDs.removeAll()
        maintenanceGeneration &+= 1
    }

    public func stop() async {
        await shutdown()
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
        if newMode == .pushToTalk {
            hasToggleMuteIntent = false
            invalidateMaintenance()
        }
        guard previousMode == .pushToTalk || newMode == .pushToTalk else { return nil }

        isBusy = true
        return Task { [weak self] in
            guard let self else { return }
            if newMode == .pushToTalk {
                await self.enqueueInactiveManagedTargetsForRestoration()
            }
            guard await self.muteIfNeeded(forceForSafety: true).succeeded else { return }
            if newMode == .pushToTalk, !self.pendingRestoreNames.isEmpty {
                await self.restartMaintenance(emitFeedback: false).value
            }
        }
    }

    public func selectTarget(_ newTarget: AudioTargetSelection) async {
        guard newTarget.id != target.id else { return }
        targetSelectionGeneration &+= 1
        let selectionGeneration = targetSelectionGeneration

        let previousDevices = (try? await resolvedTargetDevices()) ?? []
        guard selectionGeneration == targetSelectionGeneration else { return }
        let previousUIDs = activeTargetUIDs.isEmpty
            ? Set(previousDevices.map(\.uid))
            : activeTargetUIDs
        if mode == .pushToTalk {
            guard await muteIfNeeded(forceForSafety: true).succeeded else { return }
            guard selectionGeneration == targetSelectionGeneration else { return }
            isHotKeyPressed = false
        } else if !hasToggleMuteIntent {
            isHotKeyPressed = false
            guard await unmuteIfNeeded(onlyWithReceipts: true) else { return }
            guard selectionGeneration == targetSelectionGeneration else { return }
        }

        guard selectionGeneration == targetSelectionGeneration else { return }
        target = newTarget
        keepAllInputsMuted = false
        invalidateMaintenance()
        await refresh()
        guard selectionGeneration == targetSelectionGeneration else { return }

        if mode == .pushToTalk {
            await muteIfNeeded(forceForSafety: true)
            let currentUIDs = Set(
                ((try? await resolvedTargetDevices()) ?? []).map(\.uid)
            )
            _ = await restoreManagedDevices(
                previousDevices.filter { !currentUIDs.contains($0.uid) }
            )
        } else if hasToggleMuteIntent, maintainsMuteOnInputChange {
            activeTargetUIDs = previousUIDs
            await restartMaintenance(emitFeedback: true).value
        } else {
            activeTargetUIDs = Set(
                ((try? await resolvedTargetDevices()) ?? []).map(\.uid)
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
        await acquireOperation()
        guard mode == .toggle,
              hasToggleMuteIntent || status.canToggle else {
            releaseOperation()
            return
        }
        var shouldRestartMaintenance = false
        if hasToggleMuteIntent {
            hasToggleMuteIntent = false
            invalidateMaintenance()
            enqueueManagedActiveTargetsForRestoration()
            await unmuteIfNeeded(
                onlyWithReceipts: true,
                operationAlreadyAcquired: true
            )
            shouldRestartMaintenance = true
        } else if shouldUnmuteTargets {
            await unmuteIfNeeded(operationAlreadyAcquired: true)
        } else {
            let result = await muteIfNeeded(operationAlreadyAcquired: true)
            if maintainsMuteOnInputChange, !result.confirmedUIDs.isEmpty {
                hasToggleMuteIntent = true
                activeTargetUIDs = Set(
                    ((try? await resolvedTargetDevices()) ?? []).map(\.uid)
                )
            }
        }
        releaseOperation()
        if shouldRestartMaintenance {
            await restartMaintenance(emitFeedback: false).value
        }
    }

    public func setMaintainsMuteOnInputChange(_ enabled: Bool) async {
        guard enabled != maintainsMuteOnInputChange else { return }
        maintenancePreferenceGeneration &+= 1
        let preferenceGeneration = maintenancePreferenceGeneration
        maintainsMuteOnInputChange = enabled
        invalidateMaintenance()

        if !enabled {
            hasToggleMuteIntent = false
            await restartMaintenance(emitFeedback: false).value
            return
        }

        guard mode == .toggle,
              let devices = try? await resolvedTargetDevices(),
              !devices.isEmpty else { return }
        guard preferenceGeneration == maintenancePreferenceGeneration,
              maintainsMuteOnInputChange else { return }
        var allManagedAndMuted = true
        for device in devices {
            guard sessionManagedUIDs.contains(device.uid),
                  let snapshot = try? await audioController.snapshot(deviceUID: device.uid),
                  snapshot.muteState == .muted else {
                allManagedAndMuted = false
                break
            }
            guard preferenceGeneration == maintenancePreferenceGeneration,
                  maintainsMuteOnInputChange else { return }
        }
        if allManagedAndMuted,
           preferenceGeneration == maintenancePreferenceGeneration,
           maintainsMuteOnInputChange {
            hasToggleMuteIntent = true
            activeTargetUIDs = Set(devices.map(\.uid))
        }
    }

    public func refresh() async {
        await refreshStatus()
    }

    @discardableResult
    public func cancelActiveHotKeyGesture() async -> Bool {
        guard isHotKeyPressed else { return true }
        if mode == .pushToTalk {
            guard await muteIfNeeded(forceForSafety: true).succeeded else { return false }
        }
        isHotKeyPressed = false
        return true
    }

    private func enqueueAudioEvent(_ event: AudioHardwareEvent) {
        switch event.kind {
        case .deviceListChanged, .defaultInputChanged:
            pendingInventoryRefresh = true
        case .controlValueChanged:
            guard controlEventAffectsCurrentTarget(event) else { return }
            pendingControlObjectIDs.insert(event.objectID)
        }
        invalidateMaintenance()
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
            if !pendingRestoreNames.isEmpty {
                _ = restartMaintenance(emitFeedback: true)
            }
        } else {
            if target == .allInputs,
               keepAllInputsMuted,
               !shouldUnmuteTargets,
               !(hasToggleMuteIntent && maintainsMuteOnInputChange) {
                await muteIfNeeded()
            }
            if (hasToggleMuteIntent && maintainsMuteOnInputChange)
                || !pendingRestoreNames.isEmpty {
                _ = restartMaintenance(emitFeedback: true)
            }
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

    private func controlEventAffectsCurrentTarget(_ event: AudioHardwareEvent) -> Bool {
        let device = event.deviceUID.flatMap { uid in
            availableDevices.first { $0.uid == uid }
        } ?? availableDevices.first { $0.objectID == event.objectID }
        guard let device else { return false }
        if pendingRestoreNames[device.uid] != nil { return true }
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
    private func muteIfNeeded(
        forceForSafety: Bool = false,
        maintenanceGeneration expectedGeneration: UInt64? = nil,
        operationAlreadyAcquired: Bool = false
    ) async -> MuteAttemptResult {
        if !operationAlreadyAcquired {
            await acquireOperation()
        }
        defer {
            if !operationAlreadyAcquired {
                releaseOperation()
            }
        }
        if let expectedGeneration,
           expectedGeneration != maintenanceGeneration {
            return .cancelled
        }
        if !forceForSafety {
            guard status.canToggle, !shouldUnmuteTargets else {
                return MuteAttemptResult(
                    succeeded: true,
                    confirmedUIDs: [],
                    failureCount: 0
                )
            }
        }

        do {
            let devices = try await resolvedTargetDevices()
            guard !devices.isEmpty else {
                await refreshStatus()
                return .cancelled
            }

            var failures = 0
            var firstError: Error?
            var confirmedUIDs: Set<String> = []
            for device in devices {
                do {
                    if let expectedGeneration,
                       expectedGeneration != maintenanceGeneration {
                        return .cancelled
                    }
                    guard device.capabilities.isSupported else {
                        throw CoreAudioError.unsupportedDevice(uid: device.uid)
                    }
                    let snapshot = try await audioController.snapshot(deviceUID: device.uid)
                    guard expectedGeneration == nil
                            || expectedGeneration == maintenanceGeneration else {
                        return .cancelled
                    }
                    if snapshot.muteState == .muted {
                        confirmedUIDs.insert(device.uid)
                        continue
                    }
                    var receipt = await receiptStore.receipt(deviceUID: device.uid)
                    guard expectedGeneration == nil
                            || expectedGeneration == maintenanceGeneration else {
                        return .cancelled
                    }
                    var createdReceipt = false
                    if receipt == nil {
                        let preparedReceipt = AudioMutationReceipt(
                            deviceUID: device.uid,
                            originalValues: snapshot.values
                        )
                        try await receiptStore.save(preparedReceipt)
                        receipt = preparedReceipt
                        createdReceipt = true
                    } else if let storedReceipt = receipt,
                              let expandedReceipt = storedReceipt.includingNewControls(
                                from: snapshot.values
                              ),
                              expandedReceipt != storedReceipt {
                        try await receiptStore.save(expandedReceipt)
                        receipt = expandedReceipt
                    }
                    guard expectedGeneration == nil
                            || expectedGeneration == maintenanceGeneration else {
                        if createdReceipt {
                            try? await receiptStore.removeReceipt(deviceUID: device.uid)
                        }
                        return .cancelled
                    }
                    do {
                        _ = try await audioController.mute(
                            deviceUID: device.uid,
                            preserving: receipt,
                            expected: snapshot
                        )
                        let confirmed = try await audioController.snapshot(deviceUID: device.uid)
                        guard confirmed.muteState == .muted else {
                            throw CoreAudioError.muteNotConfirmed(uid: device.uid)
                        }
                        confirmedUIDs.insert(device.uid)
                        sessionManagedUIDs.insert(device.uid)
                        maintenanceFailureNames.removeValue(forKey: device.uid)
                    } catch {
                        if createdReceipt,
                           let current = try? await audioController.snapshot(deviceUID: device.uid),
                           current.values == snapshot.values {
                            try? await receiptStore.removeReceipt(deviceUID: device.uid)
                        }
                        await discardReceiptIfTopologyChanged(
                            error,
                            deviceUID: device.uid,
                            deviceName: device.name
                        )
                        throw error
                    }
                } catch {
                    if case CoreAudioError.unsupportedDevice = error {
                        // Unsupported devices are counted from their final snapshot,
                        // not again as an operation failure.
                    } else {
                        failures += 1
                    }
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
            return MuteAttemptResult(
                succeeded: failures == 0
                    && confirmedUIDs.count == Set(devices.map(\.uid)).count,
                confirmedUIDs: confirmedUIDs,
                failureCount: failures
            )
        } catch {
            status = .error(message: userFacingErrorMessage(for: error))
            return MuteAttemptResult(
                succeeded: false,
                confirmedUIDs: [],
                failureCount: 1
            )
        }
    }

    @discardableResult
    private func unmuteIfNeeded(
        onlyWithReceipts: Bool = false,
        operationAlreadyAcquired: Bool = false
    ) async -> Bool {
        if !operationAlreadyAcquired {
            await acquireOperation()
        }
        defer {
            if !operationAlreadyAcquired {
                releaseOperation()
            }
        }
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
                        sessionManagedUIDs.remove(device.uid)
                        maintenanceFailureNames.removeValue(forKey: device.uid)
                    }
                } catch {
                    await discardReceiptIfTopologyChanged(
                        error,
                        deviceUID: device.uid,
                        deviceName: device.name
                    )
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
            for device in allDevices where !device.uid.hasPrefix("unresolved-core-audio-object-") {
                lastKnownDeviceNames[device.uid] = device.name
            }
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
        let resolved: [AudioDeviceDescriptor] = switch target {
        case .systemDefault:
            if let device = devices.first(where: \.isDefaultInput) {
                [device]
            } else if let device = try await audioController.defaultInputDevice() {
                [device]
            } else {
                []
            }
        case let .device(uid, _):
            devices.filter { $0.uid == uid }
        case .allInputs:
            devices
        }
        var seenUIDs: Set<String> = []
        return resolved.filter { seenUIDs.insert($0.uid).inserted }
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

    private func invalidateMaintenance() {
        maintenanceGeneration &+= 1
    }

    private func enqueueManagedActiveTargetsForRestoration() {
        for uid in activeTargetUIDs {
            pendingRestoreNames[uid] = lastKnownDeviceNames[uid] ?? uid
        }
        activeTargetUIDs.removeAll()
    }

    private func enqueueInactiveManagedTargetsForRestoration() async {
        let currentUIDs = Set(
            ((try? await resolvedTargetDevices()) ?? []).map(\.uid)
        )
        for uid in activeTargetUIDs.subtracting(currentUIDs) {
            pendingRestoreNames[uid] = lastKnownDeviceNames[uid] ?? uid
        }
        activeTargetUIDs.formIntersection(currentUIDs)
    }

    @discardableResult
    private func restartMaintenance(
        emitFeedback: Bool
    ) -> Task<Void, Never> {
        maintenanceGeneration &+= 1
        let generation = maintenanceGeneration
        for completedID in completedMaintenanceTaskIDs {
            maintenanceTasks.removeValue(forKey: completedID)
        }
        completedMaintenanceTaskIDs.removeAll()
        let taskID = UUID()
        let task = Task { [weak self] in
            defer { self?.markMaintenanceTaskCompleted(id: taskID) }
            guard let self,
                  generation == self.maintenanceGeneration else { return }
            await self.runMaintenance(
                generation: generation,
                emitFeedback: emitFeedback
            )
        }
        maintenanceTasks[taskID] = task
        return task
    }

    private func markMaintenanceTaskCompleted(id: UUID) {
        completedMaintenanceTaskIDs.insert(id)
    }

    private func runMaintenance(
        generation: UInt64,
        emitFeedback: Bool
    ) async {
        let delays: [Duration?] = [nil, .milliseconds(100), .milliseconds(300), .milliseconds(600)]
        var result = MaintenanceAttemptResult(
            needsRetry: false,
            currentTargetFailures: 0
        )

        for delay in delays {
            guard !Task.isCancelled,
                  generation == maintenanceGeneration else { return }
            if let delay {
                do {
                    try await maintenanceSleep(delay)
                } catch {
                    return
                }
            }
            guard !Task.isCancelled,
                  generation == maintenanceGeneration else { return }
            result = await reconcileMaintenanceOnce(generation: generation)
            if !result.needsRetry { break }
        }

        guard !Task.isCancelled,
              generation == maintenanceGeneration else { return }
        await refreshStatus(
            additionalFailures: result.needsRetry ? result.currentTargetFailures : 0
        )
        if result.needsRetry, target != .allInputs, hasToggleMuteIntent {
            status = .error(
                message: NSLocalizedString(
                    "The microphone could not be controlled.",
                    comment: "Generic microphone control error"
                )
            )
        }
        publishRestorationWarnings()
        guard emitFeedback else { return }
        maintenanceFeedbackSequence &+= 1
        if restorationWarnings.isEmpty {
            maintenanceFeedback = .maintained(
                sequence: maintenanceFeedbackSequence,
                status: status
            )
        } else {
            maintenanceFeedback = .restorationFailed(
                sequence: maintenanceFeedbackSequence,
                currentStatus: status,
                devices: restorationWarnings
            )
        }
    }

    private func reconcileMaintenanceOnce(
        generation: UInt64
    ) async -> MaintenanceAttemptResult {
        guard generation == maintenanceGeneration else {
            return MaintenanceAttemptResult(
                needsRetry: false,
                currentTargetFailures: 0
            )
        }
        var needsRetry = false
        var currentTargetFailures = 0

        if mode == .toggle, hasToggleMuteIntent, maintainsMuteOnInputChange {
            let oldUIDs = activeTargetUIDs
            let desiredDevices = (try? await resolvedTargetDevices()) ?? []
            let desiredUIDs = Set(desiredDevices.map(\.uid))
            let muteResult = await muteIfNeeded(
                forceForSafety: true,
                maintenanceGeneration: generation
            )
            guard generation == maintenanceGeneration else {
                return MaintenanceAttemptResult(
                    needsRetry: false,
                    currentTargetFailures: 0
                )
            }
            needsRetry = muteResult.failureCount > 0
            currentTargetFailures = muteResult.failureCount

            if !muteResult.confirmedUIDs.isEmpty {
                for uid in oldUIDs.subtracting(desiredUIDs) {
                    pendingRestoreNames[uid] = lastKnownDeviceNames[uid] ?? uid
                }
                activeTargetUIDs = desiredUIDs
            }
        }

        let shouldProtectCurrentTarget = mode == .pushToTalk
            || (hasToggleMuteIntent && maintainsMuteOnInputChange)
        let desiredUIDs = shouldProtectCurrentTarget
            ? Set(((try? await resolvedTargetDevices()) ?? []).map(\.uid))
            : []
        let restoreFailures = await restorePendingDevices(
            excluding: desiredUIDs,
            generation: generation
        )
        return MaintenanceAttemptResult(
            needsRetry: needsRetry || restoreFailures > 0,
            currentTargetFailures: currentTargetFailures
        )
    }

    private func restorePendingDevices(
        excluding desiredUIDs: Set<String>,
        generation: UInt64
    ) async -> Int {
        let connectedByUID = Dictionary(
            availableDevices.map { ($0.uid, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var failures = 0

        for uid in pendingRestoreNames.keys.sorted() {
            guard generation == maintenanceGeneration else { break }
            guard !desiredUIDs.contains(uid) else {
                maintenanceFailureNames.removeValue(forKey: uid)
                continue
            }
            guard let device = connectedByUID[uid] else {
                maintenanceFailureNames.removeValue(forKey: uid)
                continue
            }
            guard let receipt = await receiptStore.receipt(deviceUID: uid) else {
                pendingRestoreNames.removeValue(forKey: uid)
                maintenanceFailureNames.removeValue(forKey: uid)
                continue
            }

            await acquireOperation()
            do {
                guard generation == maintenanceGeneration,
                      !desiredUIDs.contains(uid) else {
                    releaseOperation()
                    continue
                }
                try await audioController.unmute(deviceUID: uid, restoring: receipt)
                let restored = try await audioController.snapshot(deviceUID: uid)
                guard Self.snapshot(restored, matches: receipt) else {
                    throw CoreAudioError.incompleteRestoration(uid: uid)
                }
                try await receiptStore.removeReceipt(deviceUID: uid)
                sessionManagedUIDs.remove(uid)
                pendingRestoreNames.removeValue(forKey: uid)
                maintenanceFailureNames.removeValue(forKey: uid)
            } catch {
                failures += 1
                let discarded = await discardReceiptIfTopologyChanged(
                    error,
                    deviceUID: uid,
                    deviceName: device.name
                )
                if discarded {
                    pendingRestoreNames.removeValue(forKey: uid)
                } else {
                    maintenanceFailureNames[uid] = device.name
                }
                NSLog("Mutelet deferred restoration error: %@", String(describing: error))
            }
            releaseOperation()
        }
        publishRestorationWarnings()
        return failures
    }

    private func publishRestorationWarnings() {
        restorationWarnings = maintenanceFailureNames
            .map { RestorationWarningItem(deviceUID: $0.key, deviceName: $0.value) }
            .sorted {
                if $0.deviceName == $1.deviceName {
                    return $0.deviceUID < $1.deviceUID
                }
                return $0.deviceName.localizedStandardCompare($1.deviceName) == .orderedAscending
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
        guard receipt.canRestore(from: snapshot.values) else { return false }
        let currentValues = Dictionary(
            snapshot.values.map { ($0.control, $0.value) },
            uniquingKeysWith: { first, _ in first }
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
    private func discardReceiptIfTopologyChanged(
        _ error: Error,
        deviceUID: String,
        deviceName: String
    ) async -> Bool {
        guard case CoreAudioError.restorationTopologyChanged = error else {
            return false
        }
        do {
            try await receiptStore.removeReceipt(deviceUID: deviceUID)
            sessionManagedUIDs.remove(deviceUID)
            maintenanceFailureNames[deviceUID] = deviceName
            publishRestorationWarnings()
            return true
        } catch {
            return false
        }
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
                sessionManagedUIDs.remove(device.uid)
                pendingRestoreNames.removeValue(forKey: device.uid)
                maintenanceFailureNames.removeValue(forKey: device.uid)
            } catch {
                let discarded = await discardReceiptIfTopologyChanged(
                    error,
                    deviceUID: device.uid,
                    deviceName: device.name
                )
                if discarded {
                    pendingRestoreNames.removeValue(forKey: device.uid)
                }
                firstError = firstError ?? error
            }
        }

        await refreshStatus()
        publishRestorationWarnings()
        if let firstError {
            status = .error(message: userFacingErrorMessage(for: firstError))
            return false
        }
        return true
    }
}
