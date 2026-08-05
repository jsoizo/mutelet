import AppKit
import Foundation
import MuteletCore
import ServiceManagement

@MainActor
final class MuteletApplicationModel: NSObject, ObservableObject {
    @Published private(set) var preferences = MuteletPreferences()
    @Published private(set) var hotKeyError: String?
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var loginItemStatusText = NSLocalizedString(
        "Off",
        comment: "Login item disabled"
    )
    @Published private(set) var loginItemError: String?

    let coordinator: MuteCoordinator

    private let hotKeyMonitor: CarbonHotKeyMonitor
    private let preferencesStore: any MuteletPreferencesStoring
    private let hudController: MuteHUDController
    private let enablesSystemIntegrations: Bool
    private var hotKeyTask: Task<Void, Never>?
    private var targetSelectionGeneration = 0
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
                hotKeyError = String(describing: error)
            }
        }
    }

    func toggle() async {
        await coordinator.toggle()
        showHUDIfEnabled()
    }

    func selectMode(_ mode: MuteMode) {
        var updated = preferences
        updated.mode = mode
        preferences = updated
        let transition = coordinator.selectMode(mode)
        Task { [weak self] in
            await transition?.value
            guard let self else { return }
            if mode == .pushToTalk, self.preferences.showsHUD {
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
                "A shortcut must include Command or Control.",
                comment: "Invalid shortcut error"
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
            hotKeyError = String(describing: error)
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
            loginItemError = String(describing: error)
        }
        refreshLoginItemStatus()
    }

    func openSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let modernSelector = Selector(("showSettingsWindow:"))
        if !NSApplication.shared.sendAction(modernSelector, to: nil, from: nil) {
            NSApplication.shared.sendAction(
                Selector(("showPreferencesWindow:")),
                to: nil,
                from: nil
            )
        }
    }

    func openLoginItemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func stop() async {
        hotKeyTask?.cancel()
        hotKeyTask = nil
        hotKeyMonitor.stop()
        hudController.hide()
        await coordinator.stop()
        removeWorkspaceObservers()
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

    private func handleHotKey(_ event: GlobalHotKeyEvent) async {
        let mode = coordinator.mode
        await coordinator.handleHotKey(event)
        if mode == .toggle, event == .pressed {
            showHUDIfEnabled()
        }
    }

    private func showHUDIfEnabled() {
        guard preferences.showsHUD else { return }
        hudController.show(status: coordinator.status)
    }

    private func savePreferences() async {
        do {
            try await preferencesStore.save(preferences)
        } catch {
            hotKeyError = String(
                format: NSLocalizedString(
                    "Saving settings failed: %@",
                    comment: "Settings persistence error"
                ),
                String(describing: error)
            )
        }
    }

    private func refreshLoginItemStatus() {
        switch SMAppService.mainApp.status {
        case .enabled:
            launchAtLoginEnabled = true
            loginItemStatusText = NSLocalizedString("On", comment: "Login item enabled")
        case .requiresApproval:
            launchAtLoginEnabled = false
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
        Task { [weak self] in
            await self?.coordinator.stop()
        }
    }

    @objc private func workspaceDidWake() {
        Task { [weak self] in
            await self?.coordinator.start()
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
        observesWorkspace = true
    }

    private func removeWorkspaceObservers() {
        guard observesWorkspace else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        observesWorkspace = false
    }
}
