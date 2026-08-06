import AppKit
import MuteletCore
import SwiftUI

struct MuteletSettingsView: View {
    @ObservedObject var applicationModel: MuteletApplicationModel
    @ObservedObject var coordinator: MuteCoordinator

    var body: some View {
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
        .frame(width: 520, height: 370)
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var applicationModel: MuteletApplicationModel
    @ObservedObject var coordinator: MuteCoordinator

    var body: some View {
        Form {
            Section("Behavior") {
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

                Toggle("Show HUD", isOn: hudSelection)
                    .accessibilityIdentifier("settings-show-hud")
                if let preferencesError = applicationModel.preferencesError {
                    SettingsErrorText(preferencesError)
                }
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
            get: { applicationModel.preferences.mode },
            set: { applicationModel.selectMode($0) }
        )
    }

    private var targetSelection: Binding<AudioTargetSelection> {
        Binding(
            get: { applicationModel.preferences.target },
            set: { applicationModel.selectTarget($0) }
        )
    }

    private var hudSelection: Binding<Bool> {
        Binding(
            get: { applicationModel.preferences.showsHUD },
            set: { applicationModel.setShowsHUD($0) }
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

private struct ShortcutSettingsView: View {
    @ObservedObject var applicationModel: MuteletApplicationModel
    @StateObject private var recorder = HotKeyRecorder()

    var body: some View {
        Form {
            Section("Global shortcut") {
                LabeledContent("Current shortcut") {
                    Text(applicationModel.preferences.hotKey.displayName)
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
                    .disabled(applicationModel.preferences.hotKey == .default)
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
