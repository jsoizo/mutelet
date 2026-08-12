import AppKit
import MuteletCore
import SwiftUI

@MainActor
final class MuteHUDController {
    private var panels: [NSPanel] = []
    private var dismissalTask: Task<Void, Never>?
    private var presentationGeneration = 0
    private let disablesAutomaticDismissal: Bool

    init(disablesAutomaticDismissal: Bool = false) {
        self.disablesAutomaticDismissal = disablesAutomaticDismissal
    }

    func show(status: MuteStatus, preferences: HUDPreferences) {
        show(
            title: status.interfaceTitle,
            detail: status.hudDetail,
            systemImageName: status.systemImageName,
            color: status.interfaceColor,
            preferences: preferences
        )
    }

    func showPushToTalkEnabled(
        shortcut: String,
        preferences: HUDPreferences
    ) {
        show(
            title: NSLocalizedString(
                "Push to Talk",
                comment: "Push-to-talk HUD title"
            ),
            detail: String(
                format: NSLocalizedString(
                    "Hold %@ to talk",
                    comment: "Push-to-talk HUD shortcut"
                ),
                shortcut
            ),
            systemImageName: "mic.badge.plus",
            color: .accentColor,
            preferences: preferences
        )
    }

    private func show(
        title: String,
        detail: String?,
        systemImageName: String,
        color: Color,
        preferences: HUDPreferences
    ) {
        presentationGeneration += 1
        let generation = presentationGeneration
        dismissalTask?.cancel()

        let screens = NSScreen.screens
        let mainScreenIndex = NSScreen.main.flatMap { mainScreen in
            screens.firstIndex { $0 === mainScreen }
        }
        let screenIndices = HUDLayout.screenIndices(
            for: preferences.displayTarget,
            screenFrames: screens.map(\.frame),
            mainScreenIndex: mainScreenIndex,
            pointerLocation: NSEvent.mouseLocation
        )
        guard !screenIndices.isEmpty else {
            hide()
            return
        }

        ensurePanelCount(screenIndices.count)
        let activePanels = Array(panels.prefix(screenIndices.count))
        for (panel, screenIndex) in zip(activePanels, screenIndices) {
            let screen = screens[screenIndex]
            let preferredPanelSize = preferences.size.panelSize
            let panelFrame = HUDLayout.frame(
                panelSize: preferredPanelSize,
                in: screen.visibleFrame,
                position: preferences.position
            )
            let displayScale = preferredPanelSize.width > 0
                ? panelFrame.width / preferredPanelSize.width
                : 1
            panel.contentView = NSHostingView(
                rootView: MuteHUDView(
                    title: title,
                    detail: preferences.size == .compact ? nil : detail,
                    systemImageName: systemImageName,
                    color: color,
                    size: preferences.size,
                    displayScale: displayScale
                )
            )
            panel.setFrame(panelFrame, display: false)
        }
        for panel in panels.dropFirst(screenIndices.count) {
            panel.orderOut(nil)
            panel.alphaValue = 1
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            for panel in activePanels {
                panel.animator().alphaValue = 1
            }
        }
        for panel in activePanels {
            panel.orderFrontRegardless()
        }
        postAnnouncement(title: title, detail: detail)

        guard !disablesAutomaticDismissal else { return }

        dismissalTask = Task { [weak self] in
            try? await Task.sleep(for: preferences.duration.sleepDuration)
            guard !Task.isCancelled,
                  let self,
                  generation == self.presentationGeneration else { return }
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                self.finishHiding(generation: generation)
            } else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    for panel in activePanels {
                        panel.animator().alphaValue = 0
                    }
                } completionHandler: {
                    Task { @MainActor [weak self] in
                        self?.finishHiding(generation: generation)
                    }
                }
            }
        }
    }

    func hide() {
        presentationGeneration += 1
        dismissalTask?.cancel()
        dismissalTask = nil
        orderOutAllPanels()
    }

    private func finishHiding(generation: Int) {
        guard generation == presentationGeneration else { return }
        dismissalTask = nil
        orderOutAllPanels()
    }

    private func orderOutAllPanels() {
        for panel in panels {
            panel.orderOut(nil)
            panel.alphaValue = 1
        }
    }

    private func ensurePanelCount(_ count: Int) {
        while panels.count < count {
            panels.append(makePanel())
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
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

    private func postAnnouncement(title: String, detail: String?) {
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
    }
}

private struct MuteHUDView: View {
    let title: String
    let detail: String?
    let systemImageName: String
    let color: Color
    let size: HUDSize
    let displayScale: CGFloat

    var body: some View {
        VStack(spacing: size.contentSpacing) {
            Image(systemName: systemImageName)
                .font(.system(size: size.iconSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)

            VStack(spacing: size.textSpacing) {
                Text(title)
                    .font(size.titleFont)
                    .lineLimit(1)

                if let detail {
                    Text(detail)
                        .font(size.detailFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: size.maximumTextWidth)
        }
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .frame(width: size.panelSize.width, height: size.panelSize.height)
        .background {
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .fill(.regularMaterial)
                .opacity(0.5)
        }
        .scaleEffect(displayScale)
        .frame(
            width: size.panelSize.width * displayScale,
            height: size.panelSize.height * displayScale
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel([title, detail].compactMap { $0 }.joined(separator: ", "))
        .accessibilityIdentifier("mutelet-hud")
    }
}

private extension HUDSize {
    var panelSize: CGSize {
        switch self {
        case .compact: CGSize(width: 300, height: 168)
        case .standard: CGSize(width: 380, height: 224)
        case .large: CGSize(width: 480, height: 288)
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .compact: 56
        case .standard: 72
        case .large: 96
        }
    }

    var titleFont: Font {
        switch self {
        case .compact: .headline.weight(.semibold)
        case .standard: .title3.weight(.semibold)
        case .large: .title2.weight(.semibold)
        }
    }

    var detailFont: Font {
        switch self {
        case .compact: .body
        case .standard: .body
        case .large: .title3
        }
    }

    var contentSpacing: CGFloat {
        switch self {
        case .compact: 10
        case .standard: 14
        case .large: 18
        }
    }

    var textSpacing: CGFloat {
        switch self {
        case .compact: 4
        case .standard: 5
        case .large: 7
        }
    }

    var maximumTextWidth: CGFloat {
        switch self {
        case .compact: 252
        case .standard: 324
        case .large: 408
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .compact: 24
        case .standard: 28
        case .large: 36
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .compact: 20
        case .standard: 24
        case .large: 32
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .compact: 20
        case .standard: 24
        case .large: 30
        }
    }
}

private extension HUDDuration {
    var sleepDuration: Duration {
        switch self {
        case .short: .milliseconds(500)
        case .standard: .seconds(1)
        case .long: .seconds(2)
        }
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
