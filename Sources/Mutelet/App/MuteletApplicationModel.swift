import Carbon
import AppKit
import Foundation
import MuteletCore

@MainActor
final class MuteletApplicationModel: NSObject, ObservableObject {
    @Published private(set) var hotKeyError: String?

    let coordinator: MuteCoordinator

    private let hotKeyMonitor: CarbonHotKeyMonitor
    private var hotKeyTask: Task<Void, Never>?
    private var started = false
    private var observesWorkspace = false

    init(
        coordinator: MuteCoordinator,
        hotKeyMonitor: CarbonHotKeyMonitor = CarbonHotKeyMonitor()
    ) {
        self.coordinator = coordinator
        self.hotKeyMonitor = hotKeyMonitor
        super.init()
    }

    func start() async {
        guard !started else { return }
        started = true
        installWorkspaceObservers()
        await coordinator.start()

        do {
            let events = try hotKeyMonitor.register(
                keyCode: UInt32(kVK_ANSI_M),
                modifiers: [.control, .option]
            )
            hotKeyTask = Task { [weak self] in
                for await event in events {
                    guard !Task.isCancelled else { break }
                    if event == .pressed {
                        await self?.coordinator.toggle()
                    }
                }
            }
        } catch {
            hotKeyError = String(describing: error)
        }
    }

    func toggle() async {
        await coordinator.toggle()
    }

    func stop() {
        hotKeyTask?.cancel()
        hotKeyTask = nil
        hotKeyMonitor.stop()
        coordinator.stop()
        removeWorkspaceObservers()
        started = false
    }

    @objc private func workspaceWillSleep() {
        coordinator.stop()
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
