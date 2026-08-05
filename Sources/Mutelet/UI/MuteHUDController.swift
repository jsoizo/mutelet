import AppKit
import MuteletCore
import SwiftUI

@MainActor
final class MuteHUDController {
    private var panel: NSPanel?
    private var dismissalTask: Task<Void, Never>?

    func show(status: MuteStatus) {
        show(title: status.title, systemImageName: status.systemImageName)
    }

    func showPushToTalkEnabled(shortcut: String) {
        show(
            title: String(
                format: NSLocalizedString(
                    "Push to Talk enabled — Hold %@",
                    comment: "Push-to-talk enabled HUD"
                ),
                shortcut
            ),
            systemImageName: "mic.badge.plus"
        )
    }

    private func show(title: String, systemImageName: String) {
        dismissalTask?.cancel()

        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(
            rootView: MuteHUDView(title: title, systemImageName: systemImageName)
        )
        position(panel)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        dismissalTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                self.hide()
            } else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    panel.animator().alphaValue = 0
                } completionHandler: {
                    Task { @MainActor in
                        self.hide()
                    }
                }
            }
        }
    }

    func hide() {
        dismissalTask?.cancel()
        dismissalTask = nil
        panel?.orderOut(nil)
        panel?.alphaValue = 1
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 112),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .none
        return panel
    }

    private func position(_ panel: NSPanel) {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
            ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(
            NSPoint(
                x: visibleFrame.midX - panel.frame.width / 2,
                y: visibleFrame.midY - panel.frame.height / 2
            )
        )
    }
}

private struct MuteHUDView: View {
    let title: String
    let systemImageName: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImageName)
                .font(.system(size: 34, weight: .semibold))
            Text(title)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}
