import AppKit
import ColorSync
import MuteletCore
import SwiftUI

struct StatusOverlayDisplayOption: Identifiable, Hashable {
    let target: StatusOverlayDisplayTarget
    let title: String
    let isConnected: Bool

    var id: StatusOverlayDisplayTarget { target }
}

enum StatusOverlayLayout {
    static let screenMargin: CGFloat = 12
    static let dragThreshold: CGFloat = 4

    static func panelSize(
        contentStyle: StatusOverlayContentStyle,
        size: StatusOverlaySize
    ) -> CGSize {
        switch (contentStyle, size) {
        case (.iconOnly, .compact): CGSize(width: 32, height: 32)
        case (.iconOnly, .standard): CGSize(width: 44, height: 44)
        case (.iconOnly, .large): CGSize(width: 56, height: 56)
        case (.iconAndStatus, .compact): CGSize(width: 112, height: 32)
        case (.iconAndStatus, .standard): CGSize(width: 144, height: 44)
        case (.iconAndStatus, .large): CGSize(width: 176, height: 56)
        }
    }

    static func frame(
        position: NormalizedScreenPosition,
        panelSize: CGSize,
        visibleFrame: CGRect
    ) -> CGRect {
        let centerRect = availableCenterRect(panelSize: panelSize, visibleFrame: visibleFrame)
        let center = CGPoint(
            x: interpolate(position.x, from: centerRect.minX, to: centerRect.maxX),
            y: interpolate(position.y, from: centerRect.minY, to: centerRect.maxY)
        )
        return CGRect(
            x: center.x - panelSize.width / 2,
            y: center.y - panelSize.height / 2,
            width: panelSize.width,
            height: panelSize.height
        )
    }

    static func normalizedPosition(
        for center: CGPoint,
        panelSize: CGSize,
        visibleFrame: CGRect
    ) -> NormalizedScreenPosition {
        let centerRect = availableCenterRect(panelSize: panelSize, visibleFrame: visibleFrame)
        return NormalizedScreenPosition(
            x: normalized(center.x, from: centerRect.minX, to: centerRect.maxX),
            y: normalized(center.y, from: centerRect.minY, to: centerRect.maxY)
        )
    }

    static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }

    static func isDrag(from start: CGPoint, to current: CGPoint) -> Bool {
        hypot(current.x - start.x, current.y - start.y) >= dragThreshold
    }

    private static func availableCenterRect(
        panelSize: CGSize,
        visibleFrame: CGRect
    ) -> CGRect {
        let minimumX = visibleFrame.minX + screenMargin + panelSize.width / 2
        let maximumX = visibleFrame.maxX - screenMargin - panelSize.width / 2
        let minimumY = visibleFrame.minY + screenMargin + panelSize.height / 2
        let maximumY = visibleFrame.maxY - screenMargin - panelSize.height / 2
        let centerX = visibleFrame.midX
        let centerY = visibleFrame.midY
        return CGRect(
            x: minimumX <= maximumX ? minimumX : centerX,
            y: minimumY <= maximumY ? minimumY : centerY,
            width: max(0, maximumX - minimumX),
            height: max(0, maximumY - minimumY)
        )
    }

    private static func interpolate(_ value: Double, from: CGFloat, to: CGFloat) -> CGFloat {
        from + CGFloat(min(max(value, 0), 1)) * (to - from)
    }

    private static func normalized(_ value: CGFloat, from: CGFloat, to: CGFloat) -> Double {
        guard to > from else { return 0.5 }
        return Double(min(max((value - from) / (to - from), 0), 1))
    }
}

enum StatusOverlayInteraction {
    static func isActionable(
        preferences: StatusOverlayPreferences,
        mode: MuteMode,
        status: MuteStatus,
        isBusy: Bool,
        isClickInFlight: Bool,
        hasToggleMuteIntent: Bool = false
    ) -> Bool {
        preferences.togglesMuteOnClick
            && mode == .toggle
            && (status.canToggle || hasToggleMuteIntent)
            && !isBusy
            && !isClickInFlight
    }
}

enum StatusOverlayPresentationDecision: Equatable {
    case hideImmediately
    case hideAnimated
    case updateContentOnly
    case show

    static func resolve(
        preferences: StatusOverlayPreferences,
        status: MuteStatus,
        isSuspended: Bool,
        isDragging: Bool,
        hasResolvedScreen: Bool
    ) -> Self {
        if !preferences.isEnabled || isSuspended || !hasResolvedScreen {
            return .hideImmediately
        }
        if isDragging {
            return .updateContentOnly
        }
        if !preferences.visibility.includes(status) {
            return .hideAnimated
        }
        return .show
    }
}

struct StatusOverlayVisibilityState {
    private(set) var generation = 0

    mutating func invalidatePendingTransition() {
        generation += 1
    }

    mutating func beginHide() -> Int {
        invalidatePendingTransition()
        return generation
    }

    func canCompleteHide(generation: Int) -> Bool {
        self.generation == generation
    }
}

enum StatusOverlayDisplayTargetReconciler {
    static func reconcile(
        _ target: StatusOverlayDisplayTarget,
        connectedNamesByID: [String: String]
    ) -> StatusOverlayDisplayTarget {
        guard case let .display(id, lastKnownName) = target,
              let currentName = connectedNamesByID[id],
              currentName != lastKnownName else {
            return target
        }
        return .display(id: id, lastKnownName: currentName)
    }
}

enum StatusOverlayPanelFactory {
    @MainActor
    static func makePanel() -> NSPanel {
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
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .none
        return panel
    }
}

@MainActor
final class StatusOverlayController: NSObject, ObservableObject {
    @Published private(set) var displayOptions: [StatusOverlayDisplayOption] = []

    var onPreferencesChange: ((StatusOverlayPreferences) -> Void)?
    var onToggle: (() async -> MuteStatus?)?

    private var panel: NSPanel?
    private var hostingView: StatusOverlayHostingView?
    private var status: MuteStatus = .loading
    private var mode: MuteMode = .toggle
    private var isBusy = false
    private var hasToggleMuteIntent = false
    private var transientHUDEnabled = true
    private var preferences = StatusOverlayPreferences()
    private var isSuspended = false
    private var isClickInFlight = false
    private var hasReceivedUpdate = false
    private var visibilityState = StatusOverlayVisibilityState()
    private var dragStartPointer: CGPoint?
    private var dragStartOrigin: CGPoint?
    private var didDrag = false

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        refreshDisplayOptions()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func update(
        status: MuteStatus,
        mode: MuteMode,
        isBusy: Bool,
        hasToggleMuteIntent: Bool,
        preferences newPreferences: StatusOverlayPreferences,
        transientHUDEnabled: Bool
    ) {
        let previousPreferences = preferences
        let previousCenter = panel.map { CGPoint(x: $0.frame.midX, y: $0.frame.midY) }
        self.status = status
        self.mode = mode
        self.isBusy = isBusy
        self.hasToggleMuteIntent = hasToggleMuteIntent
        self.transientHUDEnabled = transientHUDEnabled
        preferences = newPreferences
        if reconcileConnectedDisplayName() {
            return
        }
        if !hasReceivedUpdate
            || previousPreferences.displayTarget != newPreferences.displayTarget {
            refreshDisplayOptions()
        }
        hasReceivedUpdate = true

        if let previousCenter,
           previousPreferences.size != newPreferences.size
                || previousPreferences.contentStyle != newPreferences.contentStyle,
           let screen = resolvedScreen() {
            let newSize = StatusOverlayLayout.panelSize(
                contentStyle: newPreferences.contentStyle,
                size: newPreferences.size
            )
            let preservedPosition = StatusOverlayLayout.normalizedPosition(
                for: previousCenter,
                panelSize: newSize,
                visibleFrame: screen.screen.visibleFrame
            )
            if preservedPosition != preferences.position {
                preferences.position = preservedPosition
                onPreferencesChange?(preferences)
            }
        }

        updatePresentation()
    }

    func suspend() {
        isSuspended = true
        hide(animated: false)
    }

    func resume() {
        isSuspended = false
        updatePresentation()
    }

    func stop() {
        isSuspended = true
        visibilityState.invalidatePendingTransition()
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }

    func resetPosition() {
        preferences.position = NormalizedScreenPosition()
        onPreferencesChange?(preferences)
        updatePresentation()
    }

    @objc private func screenParametersDidChange() {
        refreshDisplayOptions()
        updatePresentation()
    }

    private func updatePresentation() {
        let resolvedScreen = resolvedScreen()
        switch StatusOverlayPresentationDecision.resolve(
            preferences: preferences,
            status: status,
            isSuspended: isSuspended,
            isDragging: didDrag,
            hasResolvedScreen: resolvedScreen != nil
        ) {
        case .hideImmediately:
            hide(animated: false)
            return
        case .hideAnimated:
            hide(animated: true)
            return
        case .updateContentOnly:
            updateContent()
            return
        case .show:
            break
        }
        guard let resolvedScreen else { return }

        let panel = ensurePanel()
        let panelSize = StatusOverlayLayout.panelSize(
            contentStyle: preferences.contentStyle,
            size: preferences.size
        )
        panel.setFrame(
            StatusOverlayLayout.frame(
                position: preferences.position,
                panelSize: panelSize,
                visibleFrame: resolvedScreen.screen.visibleFrame
            ),
            display: false
        )
        updateContent()
        show(panel)
    }

    private func updateContent() {
        let isActionable = StatusOverlayInteraction.isActionable(
            preferences: preferences,
            mode: mode,
            status: status,
            isBusy: isBusy,
            isClickInFlight: isClickInFlight,
            hasToggleMuteIntent: hasToggleMuteIntent
        )
        let rootView = StatusOverlayView(
            status: status,
            contentStyle: preferences.contentStyle,
            size: preferences.size,
            isActionable: isActionable,
            activate: { [weak self] in self?.handleClick() }
        )
        if let hostingView {
            hostingView.rootView = rootView
            hostingView.toolTip = status.title
        }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = StatusOverlayPanelFactory.makePanel()

        let hostingView = StatusOverlayHostingView(
            rootView: StatusOverlayView(
                status: status,
                contentStyle: preferences.contentStyle,
                size: preferences.size,
                isActionable: false,
                activate: {}
            )
        )
        hostingView.onMouseDown = { [weak self] in self?.handleMouseDown() }
        hostingView.onMouseDragged = { [weak self] in self?.handleMouseDragged() }
        hostingView.onMouseUp = { [weak self] in self?.handleMouseUp() }
        panel.contentView = hostingView

        self.panel = panel
        self.hostingView = hostingView
        return panel
    }

    private func show(_ panel: NSPanel) {
        visibilityState.invalidatePendingTransition()
        if panel.isVisible {
            guard panel.alphaValue < 1 else { return }
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                panel.alphaValue = 1
            } else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    panel.animator().alphaValue = 1
                }
            }
            return
        }
        panel.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0
        panel.orderFrontRegardless()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }

    private func hide(animated: Bool) {
        guard let panel, panel.isVisible else { return }
        let generation = visibilityState.beginHide()
        guard animated,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.orderOut(nil)
            panel.alphaValue = 1
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                guard let self,
                      self.visibilityState.canCompleteHide(generation: generation) else { return }
                panel?.orderOut(nil)
                panel?.alphaValue = 1
            }
        }
    }

    private func handleMouseDown() {
        dragStartPointer = NSEvent.mouseLocation
        dragStartOrigin = panel?.frame.origin
        didDrag = false
    }

    private func handleMouseDragged() {
        guard let panel, let dragStartPointer, let dragStartOrigin else { return }
        let pointer = NSEvent.mouseLocation
        if !didDrag {
            didDrag = StatusOverlayLayout.isDrag(from: dragStartPointer, to: pointer)
        }
        guard didDrag else { return }
        panel.setFrameOrigin(
            CGPoint(
                x: dragStartOrigin.x + pointer.x - dragStartPointer.x,
                y: dragStartOrigin.y + pointer.y - dragStartPointer.y
            )
        )
    }

    private func handleMouseUp() {
        defer {
            dragStartPointer = nil
            dragStartOrigin = nil
            didDrag = false
        }
        if didDrag {
            finishDrag()
        } else {
            handleClick()
        }
    }

    private func finishDrag() {
        guard let panel,
              let selected = screenWithLargestIntersection(panelFrame: panel.frame) else {
            updatePresentation()
            return
        }
        let panelSize = StatusOverlayLayout.panelSize(
            contentStyle: preferences.contentStyle,
            size: preferences.size
        )
        preferences.displayTarget = .display(id: selected.uuid, lastKnownName: selected.name)
        preferences.position = StatusOverlayLayout.normalizedPosition(
            for: CGPoint(x: panel.frame.midX, y: panel.frame.midY),
            panelSize: panelSize,
            visibleFrame: selected.screen.visibleFrame
        )
        onPreferencesChange?(preferences)
        refreshDisplayOptions()
        updatePresentation()
    }

    private func handleClick() {
        guard StatusOverlayInteraction.isActionable(
            preferences: preferences,
            mode: mode,
            status: status,
            isBusy: isBusy,
            isClickInFlight: isClickInFlight,
            hasToggleMuteIntent: hasToggleMuteIntent
        ) else { return }
        isClickInFlight = true
        updateContent()
        Task { [weak self] in
            guard let self else { return }
            let resultingStatus = await self.onToggle?()
            if let resultingStatus, !self.transientHUDEnabled {
                self.postAnnouncement(for: resultingStatus)
            }
            self.isClickInFlight = false
            self.updateContent()
        }
    }

    private func postAnnouncement(for status: MuteStatus) {
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                NSAccessibility.NotificationUserInfoKey.announcement: status.title,
                NSAccessibility.NotificationUserInfoKey.priority:
                    NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }

    private func refreshDisplayOptions() {
        let screens = connectedScreens()
        var options = [
            StatusOverlayDisplayOption(
                target: .main,
                title: NSLocalizedString("Main screen", comment: "Status overlay display target"),
                isConnected: true
            ),
        ]
        options += screens.map {
            StatusOverlayDisplayOption(
                target: .display(id: $0.uuid, lastKnownName: $0.name),
                title: $0.name,
                isConnected: true
            )
        }
        if case let .display(id, lastKnownName) = preferences.displayTarget,
           !screens.contains(where: { $0.uuid == id }) {
            options.append(
                StatusOverlayDisplayOption(
                    target: .display(id: id, lastKnownName: lastKnownName),
                    title: String(
                        format: NSLocalizedString(
                            "%@ (Disconnected)",
                            comment: "Disconnected status overlay display"
                        ),
                        lastKnownName
                    ),
                    isConnected: false
                )
            )
        }
        if options != displayOptions {
            displayOptions = options
        }
    }

    private func reconcileConnectedDisplayName() -> Bool {
        let connectedNamesByID = Dictionary(
            uniqueKeysWithValues: connectedScreens().map { ($0.uuid, $0.name) }
        )
        let reconciled = StatusOverlayDisplayTargetReconciler.reconcile(
            preferences.displayTarget,
            connectedNamesByID: connectedNamesByID
        )
        guard reconciled != preferences.displayTarget else {
            return false
        }
        preferences.displayTarget = reconciled
        guard let onPreferencesChange else { return false }
        onPreferencesChange(preferences)
        return true
    }

    private func resolvedScreen() -> ConnectedScreen? {
        let screens = connectedScreens()
        switch preferences.displayTarget {
        case .main:
            return screens.first(where: { $0.displayID == CGMainDisplayID() }) ?? screens.first
        case let .display(id, _):
            return screens.first(where: { $0.uuid == id })
                ?? screens.first(where: { $0.displayID == CGMainDisplayID() })
                ?? screens.first
        }
    }

    private func screenWithLargestIntersection(panelFrame: CGRect) -> ConnectedScreen? {
        let pointer = NSEvent.mouseLocation
        let current = resolvedScreen()
        return connectedScreens().max { lhs, rhs in
            let lhsArea = StatusOverlayLayout.intersectionArea(panelFrame, lhs.screen.frame)
            let rhsArea = StatusOverlayLayout.intersectionArea(panelFrame, rhs.screen.frame)
            if lhsArea != rhsArea { return lhsArea < rhsArea }
            let lhsHasPointer = lhs.screen.frame.contains(pointer)
            let rhsHasPointer = rhs.screen.frame.contains(pointer)
            if lhsHasPointer != rhsHasPointer { return !lhsHasPointer }
            if lhs.uuid == current?.uuid { return false }
            if rhs.uuid == current?.uuid { return true }
            return lhs.uuid > rhs.uuid
        }
    }

    private func connectedScreens() -> [ConnectedScreen] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber,
                  let unmanagedUUID = CGDisplayCreateUUIDFromDisplayID(number.uint32Value) else {
                return nil
            }
            let uuid = unmanagedUUID.takeRetainedValue()
            return ConnectedScreen(
                screen: screen,
                displayID: number.uint32Value,
                uuid: CFUUIDCreateString(nil, uuid) as String,
                name: screen.localizedName
            )
        }
    }
}

private struct ConnectedScreen {
    let screen: NSScreen
    let displayID: CGDirectDisplayID
    let uuid: String
    let name: String
}

private final class StatusOverlayHostingView: NSHostingView<StatusOverlayView> {
    var onMouseDown: (() -> Void)?
    var onMouseDragged: (() -> Void)?
    var onMouseUp: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
    }

    override func mouseDragged(with event: NSEvent) {
        onMouseDragged?()
    }

    override func mouseUp(with event: NSEvent) {
        onMouseUp?()
    }
}

private struct StatusOverlayView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let status: MuteStatus
    let contentStyle: StatusOverlayContentStyle
    let size: StatusOverlaySize
    let isActionable: Bool
    let activate: () -> Void

    var body: some View {
        HStack(spacing: size.spacing) {
            Image(systemName: status.systemImageName)
                .font(.system(size: size.iconSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(status.statusOverlayColor)

            if contentStyle == .iconAndStatus {
                Text(status.statusOverlayTitle)
                    .font(size.font)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, contentStyle == .iconOnly ? 0 : size.horizontalPadding)
        .frame(
            width: StatusOverlayLayout.panelSize(contentStyle: contentStyle, size: size).width,
            height: StatusOverlayLayout.panelSize(contentStyle: contentStyle, size: size).height
        )
        .background {
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .fill(
                    reduceTransparency
                        ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                        : AnyShapeStyle(.regularMaterial)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: size.cornerRadius)
                        .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                }
        }
        .contentShape(Rectangle())
        .id(status.statusOverlayAnimationID)
        .transition(.opacity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: status.statusOverlayAnimationID)
        .help(status.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.title)
        .accessibilityHint("Drag to move the persistent status.")
        .modifier(StatusOverlayActionAccessibility(isActionable: isActionable, activate: activate))
        .accessibilityIdentifier("mutelet-status-overlay")
    }
}

private struct StatusOverlayActionAccessibility: ViewModifier {
    let isActionable: Bool
    let activate: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isActionable {
            content
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    activate()
                }
        } else {
            content
        }
    }
}

private extension StatusOverlaySize {
    var iconSize: CGFloat {
        switch self {
        case .compact: 16
        case .standard: 22
        case .large: 28
        }
    }

    var font: Font {
        switch self {
        case .compact: .caption2.weight(.semibold)
        case .standard: .caption.weight(.semibold)
        case .large: .body.weight(.semibold)
        }
    }

    var spacing: CGFloat {
        switch self {
        case .compact: 5
        case .standard: 7
        case .large: 9
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .compact: 9
        case .standard: 12
        case .large: 15
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .compact: 10
        case .standard: 14
        case .large: 18
        }
    }
}

extension MuteStatus {
    fileprivate var statusOverlayColor: Color {
        switch self {
        case .live:
            .green
        case .muted:
            .red
        case .mixed, .partial, .error:
            .orange
        case .loading, .unavailable, .disconnected, .unsupported:
            .secondary
        }
    }

    var statusOverlayTitle: String {
        switch self {
        case .live:
            NSLocalizedString("Live", comment: "Persistent status short title")
        case .muted:
            NSLocalizedString("Muted", comment: "Persistent status short title")
        case .mixed:
            NSLocalizedString("Mixed", comment: "Persistent status short title")
        case .loading:
            NSLocalizedString("Checking…", comment: "Persistent status short title")
        case .unavailable:
            NSLocalizedString("No input", comment: "Persistent status short title")
        case .disconnected:
            NSLocalizedString("Disconnected", comment: "Persistent status short title")
        case .unsupported:
            NSLocalizedString("Unsupported", comment: "Persistent status short title")
        case .partial:
            NSLocalizedString("Partial", comment: "Persistent status short title")
        case .error:
            NSLocalizedString("Error", comment: "Persistent status short title")
        }
    }

    fileprivate var statusOverlayAnimationID: String {
        "\(systemImageName)-\(statusOverlayTitle)"
    }
}
