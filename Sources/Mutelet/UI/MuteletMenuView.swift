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
        .disabled(!coordinator.status.canToggle || coordinator.isBusy)

        Divider()

        Text("Shortcut: ⌃⌥M")

        if let hotKeyError = applicationModel.hotKeyError {
            Text("Shortcut unavailable")
                .help(hotKeyError)
        }

        Divider()

        Button("Quit Mutelet") {
            applicationModel.stop()
            NSApplication.shared.terminate(nil)
        }
    }

    private var toggleTitle: String {
        coordinator.status.isMuted ? "Unmute" : "Mute"
    }
}
