import MuteletCore
import SwiftUI

@main
struct MuteletApp: App {
    @StateObject private var coordinator: MuteCoordinator
    @StateObject private var applicationModel: MuteletApplicationModel

    init() {
        let coordinator = MuteCoordinator(
            audioController: CoreAudioDeviceController(),
            receiptStore: UserDefaultsAudioMutationReceiptStore()
        )
        _coordinator = StateObject(wrappedValue: coordinator)
        _applicationModel = StateObject(
            wrappedValue: MuteletApplicationModel(coordinator: coordinator)
        )
    }

    var body: some Scene {
        MenuBarExtra {
            MuteletMenuView(
                applicationModel: applicationModel,
                coordinator: coordinator
            )
        } label: {
            Image(systemName: coordinator.status.systemImageName)
                .accessibilityLabel(coordinator.status.title)
                .task {
                    await applicationModel.start()
                }
        }
        .menuBarExtraStyle(.menu)
    }
}
