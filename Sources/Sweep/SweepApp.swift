import AppKit
import SweepCore
import SwiftUI

@main
struct SweepApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Sweep", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 660)
        }
        .defaultSize(width: 1180, height: 780)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .commands { SweepCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

struct SweepCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Scan") { model.startScan() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!model.canStartScan)
            Button("Stop Scan") { model.cancelScan() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(model.phase != .scanning)
        }
        CommandMenu("Clean") {
            Button("Clean Selected…") { model.requestClean() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!model.canClean)
            Divider()
            Button("Smart Select") { model.smartSelect() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!model.hasResults)
            Button("Deselect All") { model.deselectAll() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(model.selection.isEmpty)
        }
    }
}
