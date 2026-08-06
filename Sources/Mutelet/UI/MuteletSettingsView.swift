import AppKit
import MuteletCore
import SwiftUI

struct MuteletSettingsView: View {
    @ObservedObject var applicationModel: MuteletApplicationModel
    @ObservedObject var coordinator: MuteCoordinator
    @StateObject private var recorder = HotKeyRecorder()

    var body: some View {
        Form {
            Section("Behavior") {
                Picker("Mode", selection: modeSelection) {
                    ForEach(MuteMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Picker("Input", selection: targetSelection) {
                    ForEach(settingsTargets, id: \.id) { target in
                        Text(target.title).tag(target)
                    }
                }

                Toggle("Show HUD", isOn: hudSelection)
            }

            Section("Shortcut") {
                HStack {
                    Text("Global shortcut")
                    Spacer()
                    Button(recorderButtonTitle) {
                        recorder.start { configuration in
                            Task {
                                await applicationModel.updateHotKey(configuration)
                            }
                        }
                    }
                    .accessibilityLabel("Record global shortcut")
                }
                Text("The shortcut must include Command or Control.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let hotKeyError = applicationModel.hotKeyError {
                    Text(hotKeyError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: launchAtLoginSelection)
                Text(applicationModel.loginItemStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if applicationModel.loginItemStatusText.contains("Approval") {
                    Button("Open Login Items Settings") {
                        applicationModel.openLoginItemSettings()
                    }
                }
                if let loginItemError = applicationModel.loginItemError {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("About") {
                LabeledContent("Mutelet", value: appVersion)
                Text("Apple Silicon-native microphone mute utility.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 500, height: 480)
        .onDisappear {
            recorder.stop()
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

    private var shortcutName: String {
        applicationModel.preferences.hotKey.displayName
    }

    private var recorderButtonTitle: String {
        recorder.isRecording
            ? NSLocalizedString("Press shortcut…", comment: "Shortcut recorder prompt")
            : shortcutName
    }

    private var appVersion: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String
        return version ?? NSLocalizedString("Unknown", comment: "Unknown version")
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

@MainActor
private final class HotKeyRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    private var eventMonitor: Any?

    func start(onCapture: @escaping @MainActor (GlobalHotKeyConfiguration) -> Void) {
        stop()
        isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
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
        guard modifiers.contains(.command) || modifiers.contains(.control),
              let label = keyLabel(for: event) else {
            return nil
        }
        return GlobalHotKeyConfiguration(
            keyCode: UInt32(event.keyCode),
            keyLabel: label,
            modifiers: modifiers
        )
    }

    private static func keyLabel(for event: NSEvent) -> String? {
        switch event.keyCode {
        case 36: return "↩"
        case 48: return "⇥"
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "Esc"
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
