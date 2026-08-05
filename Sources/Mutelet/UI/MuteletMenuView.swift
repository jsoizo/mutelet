import AppKit
import MuteletCore
import SwiftUI

struct MuteletMenuView: View {
    @ObservedObject var applicationModel: MuteletApplicationModel
    @ObservedObject var coordinator: MuteCoordinator

    var body: some View {
        Text(coordinator.status.title)
            .accessibilityLabel(coordinator.status.title)

        Button(toggleTitle) {
            Task {
                await applicationModel.toggle()
            }
        }
        .disabled(
            coordinator.mode != .toggle
                || !coordinator.status.canToggle
                || coordinator.isBusy
        )

        Text("Mode")

        ForEach(MuteMode.allCases) { mode in
            Button {
                applicationModel.selectMode(mode)
            } label: {
                if coordinator.mode == mode {
                    Label(mode.title, systemImage: "checkmark")
                } else {
                    Text(mode.title)
                }
            }
            .disabled(coordinator.mode == mode)
        }

        Divider()

        Text("Input")

        targetButton(.systemDefault)

        if case let .device(uid, _) = coordinator.target,
           !coordinator.availableDevices.contains(where: { $0.uid == uid }) {
            targetButton(coordinator.target)
        }

        ForEach(coordinator.availableDevices, id: \.uid) { device in
            targetButton(.device(uid: device.uid, name: device.name))
        }

        targetButton(.allInputs)

        if let targetWarning = coordinator.targetWarning {
            Text(targetWarning)
                .help(targetWarning)
        }

        Divider()

        Text(shortcutHelp)

        if let hotKeyError = applicationModel.hotKeyError {
            Text("Shortcut unavailable")
                .help(hotKeyError)
        }

        Divider()

        Button("Settings…") {
            applicationModel.openSettings()
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("Quit Mutelet") {
            NSApplication.shared.terminate(nil)
        }
    }

    private var toggleTitle: String {
        coordinator.status.isMuted
            ? NSLocalizedString("Unmute", comment: "Unmute action")
            : NSLocalizedString("Mute", comment: "Mute action")
    }

    @ViewBuilder
    private func targetButton(_ target: AudioTargetSelection) -> some View {
        Button {
            applicationModel.selectTarget(target)
        } label: {
            if coordinator.target.id == target.id {
                Label(target.title, systemImage: "checkmark")
            } else {
                Text(target.title)
            }
        }
        .disabled(coordinator.target.id == target.id || coordinator.isBusy)
    }

    private var shortcutHelp: String {
        switch coordinator.mode {
        case .toggle:
            String(
                format: NSLocalizedString("Shortcut: %@", comment: "Shortcut help"),
                applicationModel.preferences.hotKey.displayName
            )
        case .pushToTalk:
            String(
                format: NSLocalizedString("Hold %@ to talk", comment: "Push-to-talk help"),
                applicationModel.preferences.hotKey.displayName
            )
        }
    }
}
