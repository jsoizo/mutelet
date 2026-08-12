import AppKit
import MuteletCore
import SwiftUI

struct MuteletSettingsView: View {
    @ObservedObject var applicationModel: MuteletApplicationModel
    @ObservedObject var coordinator: MuteCoordinator

    var body: some View {
        VStack(spacing: 0) {
            settingsNotices

            TabView {
                GeneralSettingsView(
                    applicationModel: applicationModel,
                    coordinator: coordinator
                )
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

                ShortcutSettingsView(applicationModel: applicationModel)
                    .tabItem {
                        Label("Shortcut", systemImage: "keyboard")
                    }

                AboutSettingsView()
                    .tabItem {
                        Label("About", systemImage: "info.circle")
                    }
            }
        }
        .frame(width: 600, height: 720)
    }

    @ViewBuilder
    private var settingsNotices: some View {
        if applicationModel.preferencesRecoveryWarning != nil
            || applicationModel.preferencesError != nil {
            VStack(alignment: .leading, spacing: 6) {
                if let recoveryWarning = applicationModel.preferencesRecoveryWarning {
                    SettingsWarningText(recoveryWarning)
                        .accessibilityIdentifier("settings-preferences-recovery-warning")
                }
                if let preferencesError = applicationModel.preferencesError {
                    SettingsErrorText(preferencesError)
                        .accessibilityIdentifier("settings-preferences-save-error")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var applicationModel: MuteletApplicationModel
    @ObservedObject var coordinator: MuteCoordinator

    var body: some View {
        Form {
            Section("Microphone controls") {
                Picker("Mode", selection: modeSelection) {
                    ForEach(MuteMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .accessibilityIdentifier("settings-mode-picker")

                Picker("Input", selection: targetSelection) {
                    ForEach(settingsTargets, id: \.id) { target in
                        Text(target.title).tag(target)
                    }
                }
                .accessibilityIdentifier("settings-input-picker")
            }

            Section("On-screen display") {
                Text("After actions")
                    .font(.headline)

                Toggle("Show status after actions", isOn: hudSelection)
                    .accessibilityIdentifier("settings-show-hud")

                Picker("Size", selection: hudSizeSelection) {
                    ForEach(HUDSize.allCases, id: \.self) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings-hud-size")

                LabeledContent("Position") {
                    HStack(spacing: 10) {
                        Text(applicationModel.preferences.hud.position.title)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(width: 92, alignment: .trailing)
                            .accessibilityIdentifier("settings-hud-position-value")

                        HUDPositionGrid(selection: hudPositionSelection)
                    }
                }

                Picker("Screen", selection: hudDisplayTargetSelection) {
                    ForEach(HUDDisplayTarget.allCases, id: \.self) { target in
                        Text(target.title).tag(target)
                    }
                }
                .accessibilityIdentifier("settings-hud-screen")

                Picker("Duration", selection: hudDurationSelection) {
                    ForEach(HUDDuration.allCases, id: \.self) { duration in
                        Text(duration.title).tag(duration)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings-hud-duration")

                Button("Preview HUD") {
                    applicationModel.previewHUD()
                }
                .accessibilityIdentifier("settings-hud-preview")

                Divider()

                StatusOverlaySettingsView(
                    applicationModel: applicationModel,
                    coordinator: coordinator,
                    controller: applicationModel.statusOverlayController
                )
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: launchAtLoginSelection)
                    .accessibilityIdentifier("settings-launch-at-login")
                Text(applicationModel.loginItemStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if applicationModel.loginItemRequiresApproval {
                    Button("Open Login Items Settings") {
                        applicationModel.openLoginItemSettings()
                    }
                }
                if let loginItemError = applicationModel.loginItemError {
                    SettingsErrorText(loginItemError)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            applicationModel.refreshLoginItemStatus()
        }
    }

    private var modeSelection: Binding<MuteMode> {
        Binding(
            get: { applicationModel.preferences.microphone.mode },
            set: { applicationModel.selectMode($0) }
        )
    }

    private var targetSelection: Binding<AudioTargetSelection> {
        Binding(
            get: { applicationModel.preferences.microphone.target },
            set: { applicationModel.selectTarget($0) }
        )
    }

    private var hudSelection: Binding<Bool> {
        Binding(
            get: { applicationModel.preferences.hud.isEnabled },
            set: { applicationModel.setShowsHUD($0) }
        )
    }

    private var hudSizeSelection: Binding<HUDSize> {
        Binding(
            get: { applicationModel.preferences.hud.size },
            set: { size in
                Task { @MainActor in
                    applicationModel.setHUDSize(size)
                }
            }
        )
    }

    private var hudPositionSelection: Binding<HUDPosition> {
        Binding(
            get: { applicationModel.preferences.hud.position },
            set: { applicationModel.setHUDPosition($0) }
        )
    }

    private var hudDisplayTargetSelection: Binding<HUDDisplayTarget> {
        Binding(
            get: { applicationModel.preferences.hud.displayTarget },
            set: { applicationModel.setHUDDisplayTarget($0) }
        )
    }

    private var hudDurationSelection: Binding<HUDDuration> {
        Binding(
            get: { applicationModel.preferences.hud.duration },
            set: { duration in
                Task { @MainActor in
                    applicationModel.setHUDDuration(duration)
                }
            }
        )
    }

    private var launchAtLoginSelection: Binding<Bool> {
        Binding(
            get: { applicationModel.launchAtLoginEnabled },
            set: { applicationModel.setLaunchAtLogin($0) }
        )
    }

    private var settingsTargets: [AudioTargetSelection] {
        var targets: [AudioTargetSelection] = [.systemDefault]
        targets += coordinator.availableDevices.map {
            .device(uid: $0.uid, name: $0.name)
        }
        if case .device = coordinator.target,
           !targets.contains(where: { $0.id == coordinator.target.id }) {
            targets.append(coordinator.target)
        }
        targets.append(.allInputs)
        return targets
    }
}

private struct StatusOverlaySettingsView: View {
    @ObservedObject var applicationModel: MuteletApplicationModel
    @ObservedObject var coordinator: MuteCoordinator
    @ObservedObject var controller: StatusOverlayController

    var body: some View {
        Text("Persistent status")
            .font(.headline)

        Toggle("Show persistent status", isOn: enabledSelection)
            .accessibilityIdentifier("settings-status-overlay-enabled")

        Picker("Show", selection: visibilitySelection) {
            ForEach(StatusOverlayVisibility.allCases, id: \.self) { visibility in
                Text(visibility.title).tag(visibility)
            }
        }
        .accessibilityIdentifier("settings-status-overlay-visibility")

        Picker("Content", selection: contentStyleSelection) {
            ForEach(StatusOverlayContentStyle.allCases, id: \.self) { contentStyle in
                Text(contentStyle.title).tag(contentStyle)
            }
        }
        .accessibilityIdentifier("settings-status-overlay-content")

        Picker("Size", selection: sizeSelection) {
            ForEach(StatusOverlaySize.allCases, id: \.self) { size in
                Text(size.title).tag(size)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("settings-status-overlay-size")

        Picker("Screen", selection: displayTargetSelection) {
            ForEach(controller.displayOptions) { option in
                Text(option.title).tag(option.target)
            }
        }
        .accessibilityIdentifier("settings-status-overlay-screen")

        Toggle("Click to toggle mute", isOn: togglesMuteOnClickSelection)
            .accessibilityIdentifier("settings-status-overlay-click-toggle")

        Text(
            coordinator.mode == .pushToTalk
                ? "In Push to Talk mode, only status display and dragging are available."
                : "In Toggle mode, click the persistent status to toggle mute."
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        Button("Reset Position") {
            applicationModel.resetStatusOverlayPosition()
        }
        .accessibilityIdentifier("settings-status-overlay-reset-position")
    }

    private var enabledSelection: Binding<Bool> {
        Binding(
            get: { applicationModel.preferences.statusOverlay.isEnabled },
            set: { applicationModel.setStatusOverlayEnabled($0) }
        )
    }

    private var visibilitySelection: Binding<StatusOverlayVisibility> {
        Binding(
            get: { applicationModel.preferences.statusOverlay.visibility },
            set: { applicationModel.setStatusOverlayVisibility($0) }
        )
    }

    private var contentStyleSelection: Binding<StatusOverlayContentStyle> {
        Binding(
            get: { applicationModel.preferences.statusOverlay.contentStyle },
            set: { applicationModel.setStatusOverlayContentStyle($0) }
        )
    }

    private var sizeSelection: Binding<StatusOverlaySize> {
        Binding(
            get: { applicationModel.preferences.statusOverlay.size },
            set: { size in
                Task { @MainActor in
                    applicationModel.setStatusOverlaySize(size)
                }
            }
        )
    }

    private var displayTargetSelection: Binding<StatusOverlayDisplayTarget> {
        Binding(
            get: { applicationModel.preferences.statusOverlay.displayTarget },
            set: { applicationModel.setStatusOverlayDisplayTarget($0) }
        )
    }

    private var togglesMuteOnClickSelection: Binding<Bool> {
        Binding(
            get: { applicationModel.preferences.statusOverlay.togglesMuteOnClick },
            set: { applicationModel.setStatusOverlayTogglesMuteOnClick($0) }
        )
    }
}

private struct HUDPositionGrid: View {
    @Binding var selection: HUDPosition
    @FocusState private var focusedPosition: HUDPosition?
    @State private var hoveredPosition: HUDPosition?

    var body: some View {
        VStack(spacing: 6) {
            ForEach(HUDVerticalPosition.allCases, id: \.self) { vertical in
                HStack(spacing: 6) {
                    ForEach(HUDHorizontalPosition.allCases, id: \.self) { horizontal in
                        let position = HUDPosition(
                            horizontal: horizontal,
                            vertical: vertical
                        )
                        positionButton(position)
                    }
                }
            }
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("HUD position")
        .accessibilityIdentifier("settings-hud-position-grid")
    }

    private func positionButton(_ position: HUDPosition) -> some View {
        let isSelected = selection == position
        let isFocused = focusedPosition == position
        let isHovered = hoveredPosition == position
        return Button {
            selection = position
        } label: {
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    isSelected
                        ? Color.accentColor
                        : Color(nsColor: .controlBackgroundColor)
                )
                .frame(width: 32, height: 18)
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(
                            isFocused
                                ? Color.accentColor
                                : isHovered
                                    ? Color.accentColor.opacity(0.8)
                                    : isSelected
                                        ? Color.accentColor.opacity(0.8)
                                        : Color.secondary.opacity(0.35),
                            lineWidth: isFocused ? 2 : 1
                        )
                }
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                    }
                }
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focusedPosition, equals: position)
        .onHover { isHovering in
            hoveredPosition = isHovering ? position : nil
        }
        .accessibilityLabel(position.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(
            "settings-hud-position-\(position.vertical.rawValue)-\(position.horizontal.rawValue)"
        )
    }
}

private extension HUDSize {
    var title: String {
        switch self {
        case .compact:
            NSLocalizedString("Compact", comment: "Compact HUD size")
        case .standard:
            NSLocalizedString("Standard", comment: "Standard HUD size or duration")
        case .large:
            NSLocalizedString("Large", comment: "Large HUD size")
        }
    }
}

private extension StatusOverlayVisibility {
    var title: String {
        switch self {
        case .always:
            NSLocalizedString("Always", comment: "Persistent status visibility")
        case .whenPotentiallyLive:
            NSLocalizedString(
                "When live or status is unknown",
                comment: "Persistent status visibility"
            )
        }
    }
}

private extension StatusOverlayContentStyle {
    var title: String {
        switch self {
        case .iconOnly:
            NSLocalizedString("Icon only", comment: "Persistent status content")
        case .iconAndStatus:
            NSLocalizedString("Icon and status", comment: "Persistent status content")
        }
    }
}

private extension StatusOverlaySize {
    var title: String {
        switch self {
        case .compact:
            NSLocalizedString("Compact", comment: "Persistent status size")
        case .standard:
            NSLocalizedString("Standard", comment: "Persistent status size")
        case .large:
            NSLocalizedString("Large", comment: "Persistent status size")
        }
    }
}

private extension HUDDisplayTarget {
    var title: String {
        switch self {
        case .pointer:
            NSLocalizedString("Screen with pointer", comment: "HUD display target")
        case .main:
            NSLocalizedString("Main screen", comment: "HUD display target")
        case .all:
            NSLocalizedString("All screens", comment: "HUD display target")
        }
    }
}

private extension HUDDuration {
    var title: String {
        switch self {
        case .short:
            NSLocalizedString(
                "Short (0.5 seconds)",
                comment: "Short HUD duration with seconds"
            )
        case .standard:
            NSLocalizedString(
                "Standard (1 second)",
                comment: "Standard HUD duration with seconds"
            )
        case .long:
            NSLocalizedString(
                "Long (2 seconds)",
                comment: "Long HUD duration with seconds"
            )
        }
    }
}

private extension HUDPosition {
    var title: String {
        switch (vertical, horizontal) {
        case (.top, .leading):
            NSLocalizedString("Top left", comment: "HUD position")
        case (.top, .center):
            NSLocalizedString("Top center", comment: "HUD position")
        case (.top, .trailing):
            NSLocalizedString("Top right", comment: "HUD position")
        case (.center, .leading):
            NSLocalizedString("Center left", comment: "HUD position")
        case (.center, .center):
            NSLocalizedString("Center", comment: "HUD position")
        case (.center, .trailing):
            NSLocalizedString("Center right", comment: "HUD position")
        case (.bottom, .leading):
            NSLocalizedString("Bottom left", comment: "HUD position")
        case (.bottom, .center):
            NSLocalizedString("Bottom center", comment: "HUD position")
        case (.bottom, .trailing):
            NSLocalizedString("Bottom right", comment: "HUD position")
        }
    }
}

private struct ShortcutSettingsView: View {
    @ObservedObject var applicationModel: MuteletApplicationModel
    @StateObject private var recorder = HotKeyRecorder()

    var body: some View {
        Form {
            Section("Global shortcut") {
                LabeledContent("Current shortcut") {
                    Text(applicationModel.preferences.shortcuts.primary.displayName)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }

                HStack {
                    Button(recorder.isRecording ? "Cancel" : "Record Shortcut…") {
                        if recorder.isRecording {
                            recorder.stop()
                        } else {
                            recorder.start { configuration in
                                Task {
                                    await applicationModel.updateHotKey(configuration)
                                }
                            }
                        }
                    }
                    .accessibilityLabel("Record global shortcut")

                    Button("Restore Default") {
                        recorder.stop()
                        Task {
                            await applicationModel.updateHotKey(.default)
                        }
                    }
                    .disabled(applicationModel.preferences.shortcuts.primary == .default)
                }

                if recorder.isRecording {
                    Label("Press shortcut…", systemImage: "keyboard.badge.ellipsis")
                        .foregroundStyle(.tint)
                }

                Text("Use at least one modifier including Command or Control. Press Escape to cancel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let hotKeyError = applicationModel.hotKeyError {
                    SettingsErrorText(hotKeyError)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onDisappear {
            recorder.stop()
        }
    }
}

private struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .accessibilityHidden(true)

            Text("Mutelet")
                .font(.title2.weight(.semibold))

            Text(versionText)
                .foregroundStyle(.secondary)

            Text("Apple Silicon-native microphone mute utility.")
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Link("GitHub", destination: URL(string: "https://github.com/jsoizo/mutelet")!)
                Link(
                    "Privacy",
                    destination: URL(
                        string: "https://github.com/jsoizo/mutelet/blob/main/docs/PRIVACY.md"
                    )!
                )
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var versionText: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? NSLocalizedString("Unknown", comment: "Unknown version")
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "—"
        return String(
            format: NSLocalizedString("Version %@ (%@)", comment: "Version and build"),
            version,
            build
        )
    }
}

private struct SettingsErrorText: View {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.red)
    }
}

private struct SettingsWarningText: View {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
    }
}

@MainActor
private final class HotKeyRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    private var eventMonitor: Any?

    func start(onCapture: @escaping @MainActor (GlobalHotKeyConfiguration) -> Void) {
        stop()
        isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                MainActor.assumeIsolated {
                    self?.stop()
                }
                return nil
            }
            guard !event.isARepeat,
                  let configuration = Self.configuration(for: event) else {
                return event
            }
            MainActor.assumeIsolated {
                self?.stop()
                onCapture(configuration)
            }
            return nil
        }
    }

    func stop() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        isRecording = false
    }

    private static func configuration(for event: NSEvent) -> GlobalHotKeyConfiguration? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: GlobalHotKeyModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        guard let label = keyLabel(for: event) else {
            return nil
        }
        let configuration = GlobalHotKeyConfiguration(
            keyCode: UInt32(event.keyCode),
            keyLabel: label,
            modifiers: modifiers
        )
        return configuration.isValid ? configuration : nil
    }

    private static func keyLabel(for event: NSEvent) -> String? {
        switch event.keyCode {
        case 36: return "↩"
        case 48: return "⇥"
        case 49: return "Space"
        case 51: return "⌫"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            let value = event.charactersIgnoringModifiers?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            return value?.isEmpty == false ? value : nil
        }
    }
}
