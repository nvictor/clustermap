import ClustermapCore
import SwiftUI

@main
struct ClustermapApp: App {
    @State private var model = AppModel()
    @StateObject private var updater = AppUpdater()

    var body: some Scene {
        // One cluster view per app, so a single window rather than a window group.
        Window("Clustermap", id: "main") {
            MainView().environment(model)
        }
        .defaultSize(width: 1180, height: 760)
        .commands { AppCommands(model: model, updater: updater) }

        Settings {
            SettingsView().environment(model).environmentObject(updater)
        }
    }
}

struct AppCommands: Commands {
    let model: AppModel
    @ObservedObject var updater: AppUpdater

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }
        CommandGroup(after: .toolbar) {
            ForEach(Array(Signal.allCases.enumerated()), id: \.element) { index, signal in
                Button(signal.title) { model.signal = signal }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
            Divider()
            Button("Group by Namespace") { model.grouping = .namespace }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Group by Node") { model.grouping = .node }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Divider()
            Button("Zoom Out") { model.zoomOut() }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("Refresh") { model.reload() }
                .keyboardShortcut("r", modifiers: .command)
            Button("Toggle Inspector") { model.showInspector.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
            Divider()
        }
    }
}
