import AppKit
import ClustermapCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettings().tabItem { Label("Appearance", systemImage: "paintpalette") }
            UpdateSettings().tabItem { Label("Updates", systemImage: "arrow.down.circle") }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Cluster") {
                LabeledContent("Kubeconfig") {
                    Text(model.kubeconfigPath).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Button("Choose…", action: chooseKubeconfig)
                }
                if model.kubeconfigPath != KubeConfig.defaultPath {
                    Button("Use \(KubeConfig.defaultPath)") { model.kubeconfigPath = KubeConfig.defaultPath }
                }
                Toggle("Hide system namespaces", isOn: $model.hideSystem)
                    .help("Leaves out kube-system, kube-public, and kube-node-lease")
            }
            Section("Refresh") {
                Picker("Refresh every", selection: $model.refreshInterval) {
                    Text("Off").tag(0)
                    Text("10 seconds").tag(10)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("5 minutes").tag(300)
                }
            }
        }
    }

    private func chooseKubeconfig() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        // ~/.kube is a dot folder.
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: KubeConfig.expand("~/.kube"))
        panel.message = "Choose a kubeconfig file"
        if panel.runModal() == .OK, let url = panel.url {
            model.kubeconfigPath = (url.path as NSString).abbreviatingWithTildeInPath
        }
    }
}

private struct AppearanceSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Color Scheme") {
                ForEach(Palette.all) { palette in
                    Button {
                        model.paletteID = palette.id
                    } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 4).fill(palette.gradient).frame(width: 150, height: 16)
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.primary.opacity(0.15)))
                            Text(palette.name)
                            Spacer()
                            if palette.id == model.palette.id {
                                Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(palette.id == model.palette.id ? .isSelected : [])
                }
            }
            Section {
                percentage("Warning at", value: $model.thresholds.warning, range: 0.3...(model.thresholds.critical - 0.05))
                percentage("Critical at", value: $model.thresholds.critical, range: (model.thresholds.warning + 0.05)...1.5)
            } header: {
                Text("CPU and Memory")
            } footer: {
                Text("Share of the pod's limit, or of its request when it has no limit.")
            }
            Section {
                Stepper("Critical at \(Format.count(model.thresholds.restarts, "restart"))", value: $model.thresholds.restarts, in: 1...100)
                Stepper("Critical at \(Format.count(model.thresholds.events, "warning event"))", value: $model.thresholds.events, in: 1...500)
            } header: {
                Text("Restarts and Events")
            } footer: {
                Text("Counted over the last hour. One restart or one event is already a warning.")
            }
        }
    }

    private func percentage(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        Stepper(value: value, in: range, step: 0.05) {
            LabeledContent(title, value: Format.percent(value.wrappedValue))
        }
    }
}

private struct UpdateSettings: View {
    @EnvironmentObject private var updater: AppUpdater

    var body: some View {
        Form {
            Section {
                Toggle("Check for updates automatically", isOn: $updater.automaticallyChecksForUpdates)
                LabeledContent("Version", value: version)
                Button("Check Now") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            } footer: {
                if !updater.isConfigured {
                    Text("Updates are off in local builds. Release builds carry the update key.")
                }
            }
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
