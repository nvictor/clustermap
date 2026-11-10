import ClustermapCore
import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            PathBar()
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 620, minHeight: 420)
        .inspector(isPresented: $model.showInspector) {
            InspectorView().inspectorColumnWidth(min: 260, ideal: 300, max: 380)
        }
        .toolbar { toolbar }
        .navigationTitle("Clustermap")
        .navigationSubtitle(model.activeContext ?? "")
        .onExitCommand { model.zoomOut() }
        .task { model.start() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView("Connecting to the cluster…")
        case .failed(let title, let detail, let symbol):
            ContentUnavailableView {
                Label(title, systemImage: symbol)
            } description: {
                Text(detail).textSelection(.enabled)
            } actions: {
                Button("Try Again") { model.reload() }
                SettingsLink { Text("Settings…") }
            }
        case .loaded:
            if let unavailable = model.signalUnavailable {
                ContentUnavailableView(
                    unavailable.title, systemImage: model.signal.symbol, description: Text(unavailable.detail))
            } else if model.tree.children.isEmpty {
                ContentUnavailableView(
                    "No pods", systemImage: "square.dashed",
                    description: Text(model.hideSystem ? "Only system namespaces have pods. Show them in Settings." : "This cluster has no pods."))
            } else {
                TreemapCanvas()
                    .id(model.zoomNode.id)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.18), value: model.zoomNode.id)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        @Bindable var model = model

        ToolbarItem(placement: .navigation) {
            Menu {
                Picker("Context", selection: $model.context) {
                    ForEach(model.contexts, id: \.self) { Text($0).tag(Optional($0)) }
                }
                .pickerStyle(.inline)
            } label: {
                Label(model.activeContext ?? "No Context", systemImage: "server.rack").labelStyle(.titleAndIcon)
            }
            .disabled(model.contexts.isEmpty)
            .help("Kubeconfig context")
        }

        ToolbarItem(placement: .principal) {
            Picker("Signal", selection: $model.signal) {
                ForEach(Signal.allCases) { signal in
                    Label(signal.title, systemImage: signal.symbol).tag(signal)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.titleAndIcon)
            .help("Health signal shown by color")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Picker("Group By", selection: $model.grouping) {
                ForEach(Grouping.allCases) { grouping in
                    Label(grouping.title, systemImage: grouping.symbol).tag(grouping)
                }
            }
            .pickerStyle(.segmented)
            .help("Group pods by namespace or by node")

            Button {
                model.reload()
            } label: {
                if model.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .help(refreshHelp)

            Button {
                model.showInspector.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.trailing")
            }
            .help("Show or hide the inspector")
        }
    }

    private var refreshHelp: String {
        guard let fetched = model.snapshot?.fetchedAt else { return "Refresh" }
        return "Refresh (updated \(fetched.formatted(date: .omitted, time: .standard)))"
    }
}

/// Where the map is zoomed to, and how the pods in view are doing.
private struct PathBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let path = model.breadcrumb
        let scope = model.zoomNode
        HStack(spacing: 4) {
            Button {
                model.zoomOut()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(path.count < 2 && model.selectedPodID == nil)
            .help("Zoom out (Escape)")
            .accessibilityLabel("Zoom out")

            ForEach(Array(path.enumerated()), id: \.element.id) { index, node in
                if index > 0 {
                    Image(systemName: "chevron.compact.right").foregroundStyle(.tertiary)
                }
                Button(node.name) { model.zoom(into: node.id) }
                    .fontWeight(index == path.count - 1 ? .semibold : .regular)
                    .foregroundStyle(index == path.count - 1 ? .primary : .secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if let error = model.refreshError {
                Label("Refresh failed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(error)
            }
            if model.phase == .loaded {
                Text(Format.count(scope.podCount, "pod")).foregroundStyle(.secondary)
                Count(value: scope.warningCount, label: "warning", color: model.palette.fill(0.5))
                Count(value: scope.criticalCount, label: "critical", color: model.palette.fill(1))
            }
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: 30)
    }

    private struct Count: View {
        let value: Int
        let label: String
        let color: Color

        var body: some View {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(.primary.opacity(0.2)))
                Text("\(value) \(label)").monospacedDigit()
            }
            .foregroundStyle(value > 0 ? .primary : .tertiary)
            .padding(.leading, 8)
        }
    }
}
