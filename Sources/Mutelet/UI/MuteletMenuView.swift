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

        Text(shortcutHelp)

        if let hotKeyError = applicationModel.hotKeyError {
            Text("Shortcut unavailable")
                .help(hotKeyError)
        }

        Divider()

        Button("Quit Mutelet") {
            NSApplication.shared.terminate(nil)
        }
    }

    private var toggleTitle: String {
        coordinator.status.isMuted ? "Unmute" : "Mute"
    }

    private var shortcutHelp: String {
        switch coordinator.mode {
        case .toggle:
            "Shortcut: ⌃⌥M"
        case .pushToTalk:
            "Hold ⌃⌥M to talk"
        }
    }
}
