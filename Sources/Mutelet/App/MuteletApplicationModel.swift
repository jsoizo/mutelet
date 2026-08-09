import AppKit
import Foundation
import MuteletCore
import ServiceManagement

@MainActor
final class MuteletApplicationModel: NSObject, ObservableObject {
    @Published private(set) var preferences = MuteletPreferences()
    @Published private(set) var hotKeyError: String?
    @Published private(set) var preferencesError: String?
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var loginItemStatusText = NSLocalizedString(
        "Off",
        comment: "Login item disabled"
    )
    @Published private(set) var loginItemError: String?
    @Published private(set) var loginItemRequiresApproval = false

    let coordinator: MuteCoordinator

    private let hotKeyMonitor: CarbonHotKeyMonitor
    private let preferencesStore: any MuteletPreferencesStoring
    private let hudController: MuteHUDController
    private let enablesSystemIntegrations: Bool
    private var hotKeyTask: Task<Void, Never>?
    private var workspaceLifecycleTask: Task<Void, Never>?
    private var websiteHUDCaptureTask: Task<Void, Never>?
    private var targetSelectionGeneration = 0
    private var modeSelectionGeneration = 0
    private var started = false
    private var observesWorkspace = false

    init(
        coordinator: MuteCoordinator,
        hotKeyMonitor: CarbonHotKeyMonitor = CarbonHotKeyMonitor(),
        preferencesStore: any MuteletPreferencesStoring = UserDefaultsMuteletPreferencesStore(),
        hudController: MuteHUDController = MuteHUDController(),
        enablesSystemIntegrations: Bool = true
    ) {
        self.coordinator = coordinator
        self.hotKeyMonitor = hotKeyMonitor
        self.preferencesStore = preferencesStore
        self.hudController = hudController
        self.enablesSystemIntegrations = enablesSystemIntegrations
        super.init()
    }

    func start() async {
        guard !started else { return }
        started = true
        preferences = await preferencesStore.load()
        coordinator.configure(mode: preferences.mode, target: preferences.target)
        installWorkspaceObservers()
        if enablesSystemIntegrations {
            refreshLoginItemStatus()
        }
        await coordinator.start()

        if enablesSystemIntegrations {
            do {
                try installHotKey(preferences.hotKey)
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
        updated.mode = mode
        preferences = updated
        let transition = coordinator.selectMode(mode)
        Task { [weak self] in
            await transition?.value
            guard let self else { return }
            if generation == self.modeSelectionGeneration,
               mode == .pushToTalk,
               self.coordinator.mode == .pushToTalk,
               self.preferences.mode == .pushToTalk,
               self.preferences.showsHUD {
                self.hudController.showPushToTalkEnabled(
                    shortcut: self.preferences.hotKey.displayName
                )
            }
            await self.savePreferences()
        }
    }

    func selectTarget(_ target: AudioTargetSelection) {
        targetSelectionGeneration += 1
        let generation = targetSelectionGeneration
        var updated = preferences
        updated.target = target
        preferences = updated
        Task { [weak self] in
            guard let self else { return }
            await self.coordinator.selectTarget(target)
            guard generation == self.targetSelectionGeneration else { return }
            var reconciled = self.preferences
            reconciled.target = self.coordinator.target
            self.preferences = reconciled
            await self.savePreferences()
        }
    }

    func setShowsHUD(_ showsHUD: Bool) {
        var updated = preferences
        updated.showsHUD = showsHUD
        preferences = updated
        Task { [weak self] in
            await self?.savePreferences()
        }
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
        let previous = preferences.hotKey
        do {
            try installHotKey(configuration)
            var updated = preferences
            updated.hotKey = configuration
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
        await coordinator.stop()
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
        if mode == .toggle, event == .pressed {
            showHUDIfEnabled()
        }
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
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
#endif

    private func showHUDIfEnabled() {
        guard preferences.showsHUD else { return }
        hudController.show(status: coordinator.status)
    }

    private func savePreferences() async {
        do {
            try await preferencesStore.save(preferences)
            preferencesError = nil
        } catch {
            NSLog("Mutelet settings error: %@", String(describing: error))
            preferencesError = NSLocalizedString(
                "Settings could not be saved",
                comment: "Settings persistence error"
            )
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
                await self.coordinator.start()
            } else {
                await self.coordinator.stop()
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
