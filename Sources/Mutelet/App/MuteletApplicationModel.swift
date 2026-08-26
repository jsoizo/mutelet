import AppKit
import Combine
import Foundation
import MuteletCore
import ServiceManagement

@MainActor
final class MuteletApplicationModel: NSObject, ObservableObject {
    @Published private(set) var preferences = MuteletPreferences()
    @Published private(set) var hotKeyError: String?
    @Published private(set) var preferencesError: String?
    @Published private(set) var preferencesRecoveryIssues: [PreferencesRecoveryIssue] = []
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var loginItemStatusText = NSLocalizedString(
        "Off",
        comment: "Login item disabled"
    )
    @Published private(set) var loginItemError: String?
    @Published private(set) var loginItemRequiresApproval = false

    let coordinator: MuteCoordinator
    let statusOverlayController: StatusOverlayController
    let screenEdgeIndicatorController: ScreenEdgeIndicatorController

    private let hotKeyMonitor: CarbonHotKeyMonitor
    private let preferencesStore: any MuteletPreferencesStoring
    private let hudController: MuteHUDController
    private let enablesSystemIntegrations: Bool
    private var hotKeyTask: Task<Void, Never>?
    private var workspaceLifecycleTask: Task<Void, Never>?
    private var websiteHUDCaptureTask: Task<Void, Never>?
    private var preferencesSaveTask: Task<Void, Never>?
    private var statusOverlayObservation: AnyCancellable?
    private var maintenanceFeedbackObservation: AnyCancellable?
    private var hudGate = HUDPresentationGate()
    private var screenEdgeAnnouncementGate = ScreenEdgeAnnouncementGate()
    private var preferencesSaveGeneration = 0
    private var targetSelectionGeneration = 0
    private var modeSelectionGeneration = 0
    private var maintenancePreferenceGeneration = 0
    private var started = false
    private var observesWorkspace = false

    var preferencesRecoveryWarning: String? {
        guard !preferencesRecoveryIssues.isEmpty else { return nil }
        return NSLocalizedString(
            "Some settings were invalid and have been reset to defaults.",
            comment: "Settings recovery warning"
        )
    }

    var restorationWarning: String? {
        let warnings = coordinator.restorationWarnings
        guard !warnings.isEmpty else { return nil }
        if warnings.count == 1, let warning = warnings.first {
            return String(
                format: NSLocalizedString(
                    "The previous input “%@” could not be restored.",
                    comment: "Deferred input restoration warning"
                ),
                warning.deviceName
            )
        }
        return String(
            format: NSLocalizedString(
                "%d previous inputs could not be restored.",
                comment: "Deferred input restoration warning count"
            ),
            warnings.count
        )
    }

    var restorationWarningHelp: String? {
        guard !coordinator.restorationWarnings.isEmpty else { return nil }
        return coordinator.restorationWarnings.map(\.deviceName).joined(separator: ", ")
    }

    init(
        coordinator: MuteCoordinator,
        hotKeyMonitor: CarbonHotKeyMonitor = CarbonHotKeyMonitor(),
        preferencesStore: any MuteletPreferencesStoring = UserDefaultsMuteletPreferencesStore(),
        hudController: MuteHUDController = MuteHUDController(),
        statusOverlayController: StatusOverlayController = StatusOverlayController(),
        screenEdgeIndicatorController: ScreenEdgeIndicatorController =
            ScreenEdgeIndicatorController(),
        enablesSystemIntegrations: Bool = true
    ) {
        self.coordinator = coordinator
        self.hotKeyMonitor = hotKeyMonitor
        self.preferencesStore = preferencesStore
        self.hudController = hudController
        self.statusOverlayController = statusOverlayController
        self.screenEdgeIndicatorController = screenEdgeIndicatorController
        self.enablesSystemIntegrations = enablesSystemIntegrations
        super.init()
        statusOverlayController.onPreferencesChange = { [weak self] overlayPreferences in
            self?.setStatusOverlayPreferences(overlayPreferences)
        }
        statusOverlayController.onToggle = { [weak self] in
            await self?.toggleFromStatusOverlay()
        }
    }

    func start() async {
        guard !started else { return }
        started = true
        switch await preferencesStore.load() {
        case let .loaded(loadedPreferences):
            preferences = loadedPreferences
        case .defaults:
            preferences = MuteletPreferences()
        case let .recovered(recoveredPreferences, issues):
            preferences = recoveredPreferences
            preferencesRecoveryIssues = issues
            for issue in issues {
                NSLog("Mutelet settings recovery: %@", diagnosticDescription(for: issue))
            }
        }
        coordinator.configure(
            mode: preferences.microphone.mode,
            target: preferences.microphone.target,
            maintainsMuteOnInputChange: preferences.microphone.maintainsMuteOnInputChange
        )
        installWorkspaceObservers()
        if enablesSystemIntegrations {
            refreshLoginItemStatus()
        }
        await coordinator.start()
        installMaintenanceFeedbackObservation()
        installStatusOverlayObservation()
        updatePresentation()

        if enablesSystemIntegrations {
            do {
                try installHotKey(preferences.shortcuts.primary)
            } catch {
                hotKeyError = hotKeyErrorMessage(for: error)
            }
        }
    }

    func toggle() async {
        await coordinator.toggle()
        showHUDIfEnabled()
    }

    func selectMode(_ mode: MuteMode) {
        modeSelectionGeneration += 1
        let generation = modeSelectionGeneration
        var updated = preferences
        updated.microphone.mode = mode
        preferences = updated
        let transition = coordinator.selectMode(mode)
        Task { [weak self] in
            await transition?.value
            guard let self else { return }
            if generation == self.modeSelectionGeneration,
               mode == .pushToTalk,
               self.coordinator.mode == .pushToTalk,
               self.preferences.microphone.mode == .pushToTalk,
               self.preferences.hud.isEnabled {
                self.hudController.showPushToTalkEnabled(
                    shortcut: self.preferences.shortcuts.primary.displayName,
                    preferences: self.preferences.hud
                )
                // The instruction stands in for the confirmation of the mute that entering
                // the mode just performed, so an automatic remute must not overwrite it.
                self.recordHUDPresentation(
                    signature: HUDContentSignature.signature(for: self.coordinator.status)
                )
            }
            await self.savePreferences()
        }
    }

    func selectTarget(_ target: AudioTargetSelection) {
        targetSelectionGeneration += 1
        let generation = targetSelectionGeneration
        var updated = preferences
        updated.microphone.target = target
        preferences = updated
        Task { [weak self] in
            guard let self else { return }
            await self.coordinator.selectTarget(target)
            guard generation == self.targetSelectionGeneration else { return }
            var reconciled = self.preferences
            reconciled.microphone.target = self.coordinator.target
            self.preferences = reconciled
            await self.savePreferences()
        }
    }

    func setShowsHUD(_ showsHUD: Bool) {
        updateHUDPreferences { $0.isEnabled = showsHUD }
    }

    func setMaintainsMuteOnInputChange(_ enabled: Bool) {
        maintenancePreferenceGeneration += 1
        let generation = maintenancePreferenceGeneration
        var updated = preferences
        updated.microphone.maintainsMuteOnInputChange = enabled
        preferences = updated
        Task { [weak self] in
            guard let self else { return }
            guard generation == self.maintenancePreferenceGeneration else { return }
            await self.coordinator.setMaintainsMuteOnInputChange(enabled)
            guard generation == self.maintenancePreferenceGeneration else { return }
            await self.savePreferences()
        }
    }

    func setHUDSize(_ size: HUDSize) {
        updateHUDPreferences { $0.size = size }
    }

    func setHUDPosition(_ position: HUDPosition) {
        updateHUDPreferences { $0.position = position }
    }

    func setHUDDisplayTarget(_ displayTarget: HUDDisplayTarget) {
        updateHUDPreferences { $0.displayTarget = displayTarget }
    }

    func setHUDDuration(_ duration: HUDDuration) {
        updateHUDPreferences { $0.duration = duration }
    }

    func previewHUD() {
        presentStatusHUD()
    }

    func setStatusOverlayEnabled(_ isEnabled: Bool) {
        updateStatusOverlayPreferences { $0.isEnabled = isEnabled }
    }

    func setStatusOverlayVisibility(_ visibility: StatusOverlayVisibility) {
        updateStatusOverlayPreferences { $0.visibility = visibility }
    }

    func setStatusOverlayContentStyle(_ contentStyle: StatusOverlayContentStyle) {
        updateStatusOverlayPreferences { $0.contentStyle = contentStyle }
    }

    func setStatusOverlaySize(_ size: StatusOverlaySize) {
        updateStatusOverlayPreferences { $0.size = size }
    }

    func setStatusOverlayDisplayTarget(_ displayTarget: StatusOverlayDisplayTarget) {
        updateStatusOverlayPreferences { $0.displayTarget = displayTarget }
    }

    func setStatusOverlayTogglesMuteOnClick(_ togglesMuteOnClick: Bool) {
        updateStatusOverlayPreferences { $0.togglesMuteOnClick = togglesMuteOnClick }
    }

    func setScreenEdgeIndicatorEnabled(_ isEnabled: Bool) {
        updateScreenEdgePreferences { $0.isEnabled = isEnabled }
    }

    func setScreenEdgeShowsIdleOutline(_ showsIdleOutline: Bool) {
        updateScreenEdgePreferences { $0.showsIdleOutline = showsIdleOutline }
    }

    func resetStatusOverlayPosition() {
        statusOverlayController.resetPosition()
    }

    func updateHotKey(_ configuration: GlobalHotKeyConfiguration) async {
        guard configuration.isValid else {
            hotKeyError = NSLocalizedString(
                "Use at least one modifier including Command or Control.",
                comment: "Invalid shortcut error"
            )
            return
        }

        guard await coordinator.cancelActiveHotKeyGesture() else {
            hotKeyError = NSLocalizedString(
                "The microphone could not be remuted, so the shortcut was not changed.",
                comment: "Shortcut safety error"
            )
            return
        }
        let previous = preferences.shortcuts.primary
        do {
            try installHotKey(configuration)
            var updated = preferences
            updated.shortcuts.primary = configuration
            preferences = updated
            hotKeyError = nil
            await savePreferences()
        } catch {
            hotKeyError = hotKeyErrorMessage(for: error)
            try? installHotKey(previous)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard enablesSystemIntegrations else { return }
        loginItemError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Mutelet login item error: %@", String(describing: error))
            loginItemError = NSLocalizedString(
                "Login item settings could not be changed.",
                comment: "Login item update error"
            )
        }
        refreshLoginItemStatus()
    }

    func openLoginItemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func stop() async {
        await preferencesSaveTask?.value
        preferencesSaveTask = nil
        removeWorkspaceObservers()
        let pendingWorkspaceLifecycle = workspaceLifecycleTask
        workspaceLifecycleTask = nil
        await pendingWorkspaceLifecycle?.value
        hotKeyTask?.cancel()
        hotKeyTask = nil
        websiteHUDCaptureTask?.cancel()
        websiteHUDCaptureTask = nil
        hotKeyMonitor.stop()
        hudController.hide()
        statusOverlayObservation?.cancel()
        statusOverlayObservation = nil
        maintenanceFeedbackObservation?.cancel()
        maintenanceFeedbackObservation = nil
        statusOverlayController.stop()
        screenEdgeIndicatorController.stop()
        await coordinator.shutdown()
        started = false
    }

    private func installHotKey(_ configuration: GlobalHotKeyConfiguration) throws {
        hotKeyTask?.cancel()
        hotKeyTask = nil
        let events = try hotKeyMonitor.register(
            keyCode: configuration.keyCode,
            modifiers: configuration.modifiers
        )
        hotKeyTask = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled else { break }
                await self?.handleHotKey(event)
            }
        }
    }

    private func hotKeyErrorMessage(for error: Error) -> String {
        if case CarbonHotKeyError.hotKeyAlreadyRegistered = error {
            return NSLocalizedString(
                "This shortcut is already in use by another app. Choose a different shortcut.",
                comment: "Shortcut conflict error"
            )
        }
        NSLog("Mutelet shortcut error: %@", String(describing: error))
        return NSLocalizedString(
            "Shortcut unavailable",
            comment: "Shortcut registration error"
        )
    }

    private func handleHotKey(_ event: GlobalHotKeyEvent) async {
        let mode = coordinator.mode
        await coordinator.handleHotKey(event)
        presentHotKeyFeedback(
            HotKeyHUDPresentation.feedback(
                event: event,
                mode: mode,
                status: coordinator.status,
                screenEdge: preferences.screenEdge
            )
        )
    }

#if DEBUG
    func handleUITestingHotKey(_ event: GlobalHotKeyEvent) async {
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        await handleHotKey(event)
    }

    func startWebsiteHUDCaptureIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--ui-testing"),
              arguments.contains("--ui-capture-hud"),
              websiteHUDCaptureTask == nil else { return }

        websiteHUDCaptureTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            while !Task.isCancelled {
                guard let self else { return }
                await self.toggle()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
#endif

    private func showHUDIfEnabled() {
        guard preferences.hud.isEnabled else { return }
        presentStatusHUD()
    }

    // The HUD branch leaves through the same recording call that the screen edge path uses in
    // announceForScreenEdge. Recording matters as much as the presentation itself: without it
    // the self-write echo returning as .maintained would show the HUD that was just replaced.
    private func presentHotKeyFeedback(_ feedback: HotKeyFeedback) {
        guard preferences.hud.isEnabled else { return }
        let status = coordinator.status
        switch feedback {
        case .none:
            return
        case .hud:
            hudController.show(status: status, preferences: preferences.hud)
        case .screenEdge:
            // Reported from the status stream instead, where the state is settled.
            return
        }
        recordHUDPresentation(signature: HUDContentSignature.signature(for: status))
    }

    private func presentStatusHUD() {
        let status = coordinator.status
        hudController.show(status: status, preferences: preferences.hud)
        recordHUDPresentation(signature: HUDContentSignature.signature(for: status))
    }

    private func recordHUDPresentation(signature: String) {
        hudGate.recordPresentation(
            signature: signature,
            at: Date.timeIntervalSinceReferenceDate
        )
    }

    private func installMaintenanceFeedbackObservation() {
        maintenanceFeedbackObservation?.cancel()
        maintenanceFeedbackObservation = coordinator.$maintenanceFeedback
            .compactMap { $0 }
            .sink { [weak self] feedback in
                self?.presentMaintenanceHUD(feedback)
            }
    }

    private func presentMaintenanceHUD(_ feedback: AutomaticMuteMaintenanceFeedback) {
        guard preferences.hud.isEnabled else { return }
        let signature = HUDContentSignature.signature(for: feedback)
        let now = Date.timeIntervalSinceReferenceDate
        guard hudGate.allowsPresentation(signature: signature, at: now) else { return }
        hudController.showMaintenanceFeedback(feedback, preferences: preferences.hud)
        hudGate.recordPresentation(signature: signature, at: now)
    }

    private func updateHUDPreferences(
        _ update: (inout HUDPreferences) -> Void
    ) {
        var updated = preferences
        update(&updated.hud)
        preferences = updated
        updatePresentation()
        Task { [weak self] in
            await self?.savePreferences()
        }
    }

    private func updateStatusOverlayPreferences(
        _ update: (inout StatusOverlayPreferences) -> Void
    ) {
        var updated = preferences
        update(&updated.statusOverlay)
        preferences = updated
        updatePresentation()
        Task { [weak self] in
            await self?.savePreferences()
        }
    }

    private func updateScreenEdgePreferences(
        _ update: (inout ScreenEdgeIndicatorPreferences) -> Void
    ) {
        var updated = preferences
        update(&updated.screenEdge)
        preferences = updated
        updatePresentation()
        Task { [weak self] in
            await self?.savePreferences()
        }
    }

    private func setStatusOverlayPreferences(_ overlayPreferences: StatusOverlayPreferences) {
        guard overlayPreferences != preferences.statusOverlay else { return }
        var updated = preferences
        updated.statusOverlay = overlayPreferences
        preferences = updated
        updatePresentation()
        Task { [weak self] in
            await self?.savePreferences()
        }
    }

    private func installStatusOverlayObservation() {
        statusOverlayObservation?.cancel()
        statusOverlayObservation = StatusOverlayCoordinatorObservation.observe(
            coordinator
        ) { [weak self] state in
            self?.updatePresentation(state)
        }
    }

    private func updatePresentation(_ state: StatusOverlayCoordinatorState? = nil) {
        let state = state ?? StatusOverlayCoordinatorState(
            status: coordinator.status,
            mode: coordinator.mode,
            isBusy: coordinator.isBusy,
            hasToggleMuteIntent: coordinator.hasToggleMuteIntent
        )
        statusOverlayController.update(
            status: state.status,
            mode: state.mode,
            isBusy: state.isBusy,
            hasToggleMuteIntent: state.hasToggleMuteIntent,
            preferences: preferences.statusOverlay,
            transientHUDEnabled: preferences.hud.isEnabled
        )
        screenEdgeIndicatorController.update(
            status: state.status,
            mode: state.mode,
            preferences: preferences.screenEdge
        )
        announceForScreenEdge(state)
    }

    // A Push to Talk release returns before the remute settles, so announcing and recording
    // from the gesture would speak the state it just left and let the settled result through
    // as a maintenance HUD. Both follow the status the edge is showing instead.
    private func announceForScreenEdge(_ state: StatusOverlayCoordinatorState) {
        let isActive = ScreenEdgeIndicatorPresentation.suppressesHotKeyHUD(
            mode: state.mode,
            preferences: preferences.screenEdge
        )
        guard screenEdgeAnnouncementGate.announces(
            status: state.status,
            isScreenEdgeActive: isActive
        ), preferences.hud.isEnabled else { return }
        hudController.announce(status: state.status)
        recordHUDPresentation(signature: HUDContentSignature.signature(for: state.status))
    }

    private func toggleFromStatusOverlay() async -> MuteStatus? {
        guard coordinator.mode == .toggle,
              !coordinator.isBusy,
              coordinator.canToggle else { return nil }
        await coordinator.toggle()
        showHUDIfEnabled()
        return coordinator.status
    }

    private func savePreferences() async {
        preferencesSaveGeneration += 1
        let generation = preferencesSaveGeneration
        let snapshot = preferences
        let previousSave = preferencesSaveTask
        let saveTask = Task { [weak self] in
            await previousSave?.value
            guard let self else { return }
            await self.persistPreferences(snapshot)
        }
        preferencesSaveTask = saveTask
        await saveTask.value
        if generation == preferencesSaveGeneration {
            preferencesSaveTask = nil
        }
    }

    private func persistPreferences(_ snapshot: MuteletPreferences) async {
        do {
            try await preferencesStore.save(snapshot)
            preferencesError = nil
            preferencesRecoveryIssues = []
        } catch {
            NSLog("Mutelet settings error: %@", String(describing: error))
            preferencesError = NSLocalizedString(
                "Settings could not be saved",
                comment: "Settings persistence error"
            )
        }
    }

    private func diagnosticDescription(for issue: PreferencesRecoveryIssue) -> String {
        switch issue {
        case .corruptedData:
            "corrupted data"
        case let .unsupportedSchemaVersion(version):
            "unsupported schema version \(version)"
        case .invalidMicrophone:
            "invalid microphone preferences"
        case .invalidShortcut:
            "invalid shortcut"
        case .invalidHUD:
            "invalid HUD preferences"
        case .invalidStatusOverlay:
            "invalid status overlay preferences"
        case .invalidScreenEdgeIndicator:
            "invalid screen edge indicator preferences"
        case .migrationSaveFailed:
            "saving migrated preferences failed"
        }
    }

    func refreshLoginItemStatus() {
        guard enablesSystemIntegrations else { return }
        loginItemRequiresApproval = false
        switch SMAppService.mainApp.status {
        case .enabled:
            launchAtLoginEnabled = true
            loginItemStatusText = NSLocalizedString("On", comment: "Login item enabled")
        case .requiresApproval:
            launchAtLoginEnabled = true
            loginItemRequiresApproval = true
            loginItemStatusText = NSLocalizedString(
                "Approval required in System Settings",
                comment: "Login item approval status"
            )
        case .notFound:
            launchAtLoginEnabled = false
            loginItemStatusText = NSLocalizedString(
                "Unavailable",
                comment: "Login item unavailable"
            )
        case .notRegistered:
            launchAtLoginEnabled = false
            loginItemStatusText = NSLocalizedString("Off", comment: "Login item disabled")
        @unknown default:
            launchAtLoginEnabled = false
            loginItemStatusText = NSLocalizedString("Unknown", comment: "Unknown status")
        }
    }

    @objc private func workspaceWillSleep() {
        enqueueWorkspaceLifecycle(shouldRun: false)
    }

    @objc private func workspaceDidWake() {
        enqueueWorkspaceLifecycle(shouldRun: true)
    }

    @objc private func applicationDidBecomeActive() {
        if enablesSystemIntegrations {
            refreshLoginItemStatus()
        }
    }

    private func enqueueWorkspaceLifecycle(shouldRun: Bool) {
        let previous = workspaceLifecycleTask
        workspaceLifecycleTask = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            if shouldRun {
                await self.coordinator.resume()
                self.statusOverlayController.resume()
                self.screenEdgeIndicatorController.resume()
                self.updatePresentation()
            } else {
                self.statusOverlayController.suspend()
                self.screenEdgeIndicatorController.suspend()
                await self.coordinator.suspend()
            }
        }
    }

    private func installWorkspaceObservers() {
        guard !observesWorkspace else { return }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(workspaceWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(workspaceDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        observesWorkspace = true
    }

    private func removeWorkspaceObservers() {
        guard observesWorkspace else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        observesWorkspace = false
    }
}
