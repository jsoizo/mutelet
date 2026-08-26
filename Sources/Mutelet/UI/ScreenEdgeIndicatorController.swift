import AppKit
import MuteletCore
import SwiftUI

enum ScreenEdgeIndicatorLayout {
    static let glowWidth: CGFloat = 24
    static let fadeInDuration: TimeInterval = 0.1

    static func opacity(for appearance: ScreenEdgeAppearance) -> Double {
        switch appearance {
        case .hidden: 0
        case .live, .warning: 0.55
        case .idleOutline: 0.3
        }
    }

    static func color(for appearance: ScreenEdgeAppearance) -> Color {
        switch appearance {
        case .hidden, .idleOutline: .secondary
        case .live: .green
        case .warning: .orange
        }
    }
}

enum ScreenEdgeIndicatorPanelFactory {
    @MainActor
    static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // The glow covers the menu bar and Dock areas, which .floating stays below.
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .stationary,
        ]
        panel.animationBehavior = .none
        // Best effort: keeps the indicator out of screen sharing and recordings.
        panel.sharingType = .none
        return panel
    }
}

@MainActor
final class ScreenEdgeIndicatorController: NSObject {
    private var panels: [NSPanel] = []
    private var appearance: ScreenEdgeAppearance = .hidden
    private var isSuspended = false
    private var isActive = false

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func update(
        status: MuteStatus,
        mode: MuteMode,
        preferences: ScreenEdgeIndicatorPreferences
    ) {
        // Panels follow the mode rather than the gesture: building them on key down would
        // delay the glow that the gesture is supposed to confirm.
        setActive(preferences.isEnabled && mode == .pushToTalk)
        apply(
            ScreenEdgeIndicatorPresentation.appearance(
                mode: mode,
                status: status,
                preferences: preferences
            )
        )
    }

    func suspend() {
        isSuspended = true
        hide()
    }

    func resume() {
        isSuspended = false
        apply(appearance, force: true)
    }

    func stop() {
        isSuspended = true
        isActive = false
        appearance = .hidden
        tearDownPanels()
    }

    private func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            buildPanels()
        } else {
            appearance = .hidden
            tearDownPanels()
        }
    }

    private func apply(_ newAppearance: ScreenEdgeAppearance, force: Bool = false) {
        let changed = newAppearance != appearance
        appearance = newAppearance
        guard changed || force else { return }

        guard !isSuspended, newAppearance != .hidden else {
            hide()
            return
        }
        guard !panels.isEmpty else { return }

        let opacity = ScreenEdgeIndicatorLayout.opacity(for: newAppearance)
        for panel in panels {
            guard let hostingView = panel.contentView as? NSHostingView<ScreenEdgeGlowView>
            else { continue }
            hostingView.rootView = ScreenEdgeGlowView(appearance: newAppearance)
            if panel.isVisible {
                // A gesture drives five to six status refreshes; restarting the fade on each
                // of them would make the glow flicker while the key is held. Going through
                // animator() with no duration replaces a fade that is still running, which a
                // direct assignment would lose to.
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0
                    panel.animator().alphaValue = opacity
                }
            } else if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                panel.alphaValue = opacity
                panel.orderFront(nil)
            } else {
                panel.alphaValue = 0
                panel.orderFront(nil)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = ScreenEdgeIndicatorLayout.fadeInDuration
                    panel.animator().alphaValue = opacity
                }
            }
        }
    }

    private func hide() {
        // Fading out would keep showing "you can talk" after the input is muted again.
        for panel in panels {
            panel.orderOut(nil)
            panel.alphaValue = 0
        }
    }

    private func buildPanels() {
        tearDownPanels()
        panels = NSScreen.screens.map { screen in
            let panel = ScreenEdgeIndicatorPanelFactory.makePanel()
            panel.setFrame(screen.frame, display: false)
            let hostingView = NSHostingView(rootView: ScreenEdgeGlowView(appearance: .hidden))
            // The glow has to reach the physical border, including behind a notch.
            hostingView.safeAreaRegions = []
            panel.contentView = hostingView
            panel.alphaValue = 0
            return panel
        }
    }

    private func tearDownPanels() {
        for panel in panels {
            panel.orderOut(nil)
            panel.contentView = nil
        }
        panels = []
    }

    @objc private func screenParametersDidChange() {
        guard isActive else { return }
        buildPanels()
        apply(appearance, force: true)
    }
}

struct ScreenEdgeGlowView: View {
    let appearance: ScreenEdgeAppearance

    var body: some View {
        let color = ScreenEdgeIndicatorLayout.color(for: appearance)
        let width = ScreenEdgeIndicatorLayout.glowWidth
        ZStack {
            edge(color: color, startPoint: .top, endPoint: .bottom)
                .frame(height: width)
                .frame(maxHeight: .infinity, alignment: .top)
            edge(color: color, startPoint: .bottom, endPoint: .top)
                .frame(height: width)
                .frame(maxHeight: .infinity, alignment: .bottom)
            edge(color: color, startPoint: .leading, endPoint: .trailing)
                .frame(width: width)
                .frame(maxWidth: .infinity, alignment: .leading)
            edge(color: color, startPoint: .trailing, endPoint: .leading)
                .frame(width: width)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func edge(
        color: Color,
        startPoint: UnitPoint,
        endPoint: UnitPoint
    ) -> some View {
        LinearGradient(
            colors: [color, color.opacity(0)],
            startPoint: startPoint,
            endPoint: endPoint
        )
    }
}
