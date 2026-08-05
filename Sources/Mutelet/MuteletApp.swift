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
        let arguments = ProcessInfo.processInfo.arguments
        let isUITesting = arguments.contains("--ui-testing")
        let audioController: any AudioDeviceControlling = isUITesting
            ? UITestingAudioController(arguments: arguments)
            : CoreAudioDeviceController()
        let receiptStore: any AudioMutationReceiptStoring = isUITesting
            ? UITestingReceiptStore()
            : UserDefaultsAudioMutationReceiptStore()
        let coordinator = MuteCoordinator(
            audioController: audioController,
            receiptStore: receiptStore
        )
        _coordinator = StateObject(wrappedValue: coordinator)
        _applicationModel = StateObject(
            wrappedValue: MuteletApplicationModel(
                coordinator: coordinator,
                preferencesStore: isUITesting
                    ? UITestingPreferencesStore(arguments: arguments)
                    : UserDefaultsMuteletPreferencesStore(),
                enablesSystemIntegrations: !isUITesting
            )
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

        Settings {
            MuteletSettingsView(
                applicationModel: applicationModel,
                coordinator: coordinator
            )
        }
    }
}
