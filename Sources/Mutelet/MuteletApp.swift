import AppKit
import MuteletCore
import SwiftUI

@MainActor
final class MuteletAppDelegate: NSObject, NSApplicationDelegate {
    weak var applicationModel: MuteletApplicationModel?
    private var terminationPending = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let applicationModel else { return .terminateNow }
        guard !terminationPending else { return .terminateLater }
        terminationPending = true

        Task {
            await applicationModel.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@main
struct MuteletApp: App {
    @NSApplicationDelegateAdaptor(MuteletAppDelegate.self) private var appDelegate
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
                    appDelegate.applicationModel = applicationModel
                    await applicationModel.start()
                }
        }
        .menuBarExtraStyle(.menu)
    }
}
