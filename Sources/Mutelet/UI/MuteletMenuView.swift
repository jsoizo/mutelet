import AppKit
import MuteletCore
import SwiftUI

struct MuteletMenuView: View {
    @ObservedObject var applicationModel: MuteletApplicationModel
    @ObservedObject var coordinator: MuteCoordinator

    var body: some View {
        VStack(spacing: 0) {
            statusHeader

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                primaryAction

                Picker("Mode", selection: modeSelection) {
                    ForEach(MuteMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Input", selection: targetSelection) {
                    ForEach(menuTargets, id: \.id) { target in
                        Text(target.title).tag(target)
                    }
                }

                LabeledContent("Shortcut") {
                    Text(shortcutHelp)
                        .font(.system(.callout, design: .rounded, weight: .medium))
                }

                notices

#if DEBUG
                uiTestingControls
#endif
            }
            .padding(16)

            Divider()

            footer
        }
        .frame(width: 320)
        .accessibilityElement(children: .contain)
    }

    private var statusHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(coordinator.status.interfaceColor.opacity(0.16))
                Image(systemName: coordinator.status.systemImageName)
                    .font(.system(size: 22, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(coordinator.status.interfaceColor)
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(coordinator.status.interfaceTitle)
                    .font(.headline)
                Text(coordinator.status.interfaceDetail(fallbackTarget: coordinator.target.title))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(coordinator.status.title)
        .accessibilityIdentifier("mutelet-status")
    }

    private var primaryAction: some View {
        Button {
            Task {
                await applicationModel.toggle()
            }
        } label: {
            Label(toggleTitle, systemImage: toggleSymbolName)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(
            coordinator.mode != .toggle
                || !coordinator.status.canToggle
                || coordinator.isBusy
        )
        .accessibilityIdentifier("mutelet-primary-action")
    }

    @ViewBuilder
    private var notices: some View {
        if coordinator.mode == .pushToTalk {
            notice(
                shortcutHelp,
                systemImage: "hand.tap.fill",
                color: .accentColor
            )
            .accessibilityIdentifier("mutelet-push-to-talk-instruction")
        }
        if let targetWarning = coordinator.targetWarning {
            notice(
                targetWarning,
                systemImage: "exclamationmark.triangle.fill",
                color: .orange
            )
        }
        if let hotKeyError = applicationModel.hotKeyError {
            notice(hotKeyError, systemImage: "keyboard.badge.exclamationmark", color: .red)
        }
        if let preferencesError = applicationModel.preferencesError {
            notice(
                preferencesError,
                systemImage: "exclamationmark.triangle.fill",
                color: .red
            )
        }
    }

    private func notice(
        _ message: String,
        systemImage: String,
        color: Color
    ) -> some View {
        Label {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(color)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
    }

    private var footer: some View {
        HStack {
            SettingsLink {
                Label("Settings…", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)
            .accessibilityIdentifier("mutelet-settings-link")

            Spacer()

            Button("Quit Mutelet") {
                NSApplication.shared.terminate(nil)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

#if DEBUG
    @ViewBuilder
    private var uiTestingControls: some View {
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            Divider()
            HStack {
                Button {
                    Task {
                        await applicationModel.handleUITestingHotKey(.pressed)
                    }
                } label: {
                    Text(verbatim: "UI Test Hot Key Press")
                }
                Button {
                    Task {
                        await applicationModel.handleUITestingHotKey(.released)
                    }
                } label: {
                    Text(verbatim: "UI Test Hot Key Release")
                }
            }
            .controlSize(.small)
        }
    }
#endif

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

    private var menuTargets: [AudioTargetSelection] {
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

    private var toggleTitle: String {
        coordinator.status.isMuted
            ? NSLocalizedString("Unmute", comment: "Unmute action")
            : NSLocalizedString("Mute", comment: "Mute action")
    }

    private var toggleSymbolName: String {
        coordinator.status.isMuted ? "mic.fill" : "mic.slash.fill"
    }

    private var shortcutHelp: String {
        switch coordinator.mode {
        case .toggle:
            applicationModel.preferences.hotKey.displayName
        case .pushToTalk:
            String(
                format: NSLocalizedString("Hold %@ to talk", comment: "Push-to-talk help"),
                applicationModel.preferences.hotKey.displayName
            )
        }
    }
}

extension MuteStatus {
    var interfaceColor: Color {
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

    var interfaceTitle: String {
        switch self {
        case .loading:
            NSLocalizedString("Checking microphone…", comment: "Loading audio state")
        case .live:
            NSLocalizedString("Microphone on", comment: "Live microphone state")
        case .muted:
            NSLocalizedString("Microphone muted", comment: "Muted microphone state")
        case .mixed:
            NSLocalizedString("Mixed microphone state", comment: "Mixed microphone state")
        case .unavailable:
            NSLocalizedString("No input device", comment: "No audio input")
        case .disconnected:
            NSLocalizedString("Input disconnected", comment: "Disconnected input state")
        case .unsupported:
            NSLocalizedString("Unsupported input", comment: "Unsupported input state")
        case .partial:
            NSLocalizedString("Partial mute", comment: "Partial mute state")
        case .error:
            NSLocalizedString("Microphone error", comment: "Audio error state")
        }
    }

    func interfaceDetail(fallbackTarget: String) -> String {
        switch self {
        case .loading, .unavailable:
            fallbackTarget
        case let .live(deviceName),
             let .muted(deviceName),
             let .mixed(deviceName),
             let .disconnected(deviceName),
             let .unsupported(deviceName):
            deviceName
        case let .partial(deviceName, muted, live, mixed, unsupported, failed):
            String(
                format: NSLocalizedString(
                    "%@ — %d muted, %d live, %d mixed, %d unsupported, %d failed",
                    comment: "Partial mute detail"
                ),
                deviceName,
                muted,
                live,
                mixed,
                unsupported,
                failed
            )
        case let .error(message):
            message
        }
    }
}
