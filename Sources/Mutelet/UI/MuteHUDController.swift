import AppKit
import MuteletCore
import SwiftUI

@MainActor
final class MuteHUDController {
    private var panel: NSPanel?
    private var dismissalTask: Task<Void, Never>?
    private var presentationGeneration = 0

    func show(status: MuteStatus) {
        show(
            title: status.interfaceTitle,
            detail: status.hudDetail,
            systemImageName: status.systemImageName,
            color: status.interfaceColor
        )
    }

    func showPushToTalkEnabled(shortcut: String) {
        show(
            title: NSLocalizedString(
                "Push to Talk enabled",
                comment: "Push-to-talk enabled HUD title"
            ),
            detail: String(
                format: NSLocalizedString(
                    "Hold %@",
                    comment: "Push-to-talk enabled HUD shortcut"
                ),
                shortcut
            ),
            systemImageName: "mic.badge.plus",
            color: .accentColor
        )
    }

    private func show(
        title: String,
        detail: String?,
        systemImageName: String,
        color: Color
    ) {
        presentationGeneration += 1
        let generation = presentationGeneration
        dismissalTask?.cancel()

        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(
            rootView: MuteHUDView(
                title: title,
                detail: detail,
                systemImageName: systemImageName,
                color: color
            )
        )
        position(panel)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 1
        }
        panel.orderFrontRegardless()
        let announcement = [title, detail]
            .compactMap { $0 }
            .joined(separator: ", ")
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                NSAccessibility.NotificationUserInfoKey.announcement: announcement,
                NSAccessibility.NotificationUserInfoKey.priority:
                    NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )

        dismissalTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled,
                  let self,
                  generation == self.presentationGeneration else { return }
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                self.hide()
            } else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    panel.animator().alphaValue = 0
                } completionHandler: {
                    Task { @MainActor in
                        guard generation == self.presentationGeneration else { return }
                        self.hide()
                    }
                }
            }
        }
    }

    func hide() {
        presentationGeneration += 1
        dismissalTask?.cancel()
        dismissalTask = nil
        panel?.orderOut(nil)
        panel?.alphaValue = 1
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 224),
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
    let detail: String?
    let systemImageName: String
    let color: Color

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImageName)
                .font(.system(size: 72, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)

            VStack(spacing: 5) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)

                if let detail {
                    Text(detail)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 324)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(.regularMaterial)
                .opacity(0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel([title, detail].compactMap { $0 }.joined(separator: ", "))
        .accessibilityIdentifier("mutelet-hud")
    }
}

private extension MuteStatus {
    var hudDetail: String? {
        switch self {
        case let .live(deviceName),
             let .muted(deviceName),
             let .mixed(deviceName),
             let .disconnected(deviceName),
             let .unsupported(deviceName),
             let .partial(deviceName, _, _, _, _, _):
            deviceName
        case let .error(message):
            message
        case .loading, .unavailable:
            nil
        }
    }
}
