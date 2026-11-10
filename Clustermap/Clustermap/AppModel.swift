import ClustermapCore
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(title: String, detail: String, symbol: String)
    }

    // MARK: Settings (persisted)

    var kubeconfigPath: String { didSet { store(kubeconfigPath, "kubeconfigPath"); if kubeconfigPath != oldValue { reconnect() } } }
    /// Nil follows the kubeconfig's current context.
    var context: String? { didSet { store(context, "context"); if context != oldValue { reconnect() } } }
    /// Seconds between refreshes. Zero turns auto refresh off.
    var refreshInterval: Int { didSet { store(refreshInterval, "refreshInterval"); if refreshInterval != oldValue { reload() } } }
    var hideSystem: Bool { didSet { store(hideSystem, "hideSystem"); rebuild() } }
    var paletteID: String { didSet { store(paletteID, "palette") } }
    var thresholds: Thresholds { didSet { storeThresholds(); rebuild() } }
    var signal: Signal { didSet { store(signal.rawValue, "signal"); rebuild() } }
    var grouping: Grouping {
        didSet {
            store(grouping.rawValue, "grouping")
            // Node and namespace trees share no group IDs.
            if grouping != oldValue { zoomID = nil }
            rebuild()
        }
    }
    var showInspector: Bool { didSet { store(showInspector, "showInspector") } }

    // MARK: State

    private(set) var phase: Phase = .loading
    private(set) var snapshot: ClusterSnapshot?
    private(set) var tree = TreeNode(id: "cluster", name: "Cluster", kind: .cluster, size: 0, score: nil, podCount: 0)
    private(set) var contexts: [String] = []
    /// The context in use, after falling back to the kubeconfig's current one.
    private(set) var activeContext: String?
    private(set) var isRefreshing = false
    /// Set when a refresh fails while older data is still on screen.
    private(set) var refreshError: String?
    var zoomID: String?
    var selectedPodID: String?

    private let source = ClusterSource()
    private let defaults = UserDefaults.standard
    private var loop: Task<Void, Never>?
    private var generation = 0
    private let demo = ProcessInfo.processInfo.arguments.contains("--demo")

    init() {
        let defaults = UserDefaults.standard
        kubeconfigPath = defaults.string(forKey: "kubeconfigPath") ?? KubeConfig.defaultPath
        context = defaults.string(forKey: "context")
        refreshInterval = defaults.object(forKey: "refreshInterval") as? Int ?? 30
        hideSystem = defaults.bool(forKey: "hideSystem")
        paletteID = defaults.string(forKey: "palette") ?? Palette.classic.id
        signal = Signal(rawValue: defaults.string(forKey: "signal") ?? "") ?? .cpu
        grouping = Grouping(rawValue: defaults.string(forKey: "grouping") ?? "") ?? .namespace
        showInspector = defaults.object(forKey: "showInspector") as? Bool ?? true
        var thresholds = Thresholds()
        if let value = defaults.object(forKey: "warningThreshold") as? Double { thresholds.warning = value }
        if let value = defaults.object(forKey: "criticalThreshold") as? Double { thresholds.critical = value }
        if let value = defaults.object(forKey: "restartThreshold") as? Int { thresholds.restarts = value }
        if let value = defaults.object(forKey: "eventThreshold") as? Int { thresholds.events = value }
        self.thresholds = thresholds
    }

    // MARK: Derived

    var palette: Palette { Palette.named(paletteID) }

    /// The group the map is zoomed into, or the whole cluster.
    var zoomNode: TreeNode { zoomID.flatMap(tree.find) ?? tree }

    var breadcrumb: [TreeNode] { tree.path(to: zoomNode.id) ?? [tree] }

    var selectedPod: PodInfo? { snapshot?.pod(selectedPodID) }

    /// Why the active signal has nothing to show, when the cluster cannot provide it.
    var signalUnavailable: (title: String, detail: String)? {
        guard let snapshot else { return nil }
        if signal.needsMetrics, !snapshot.metricsAvailable {
            return (
                "Metrics Server not found",
                "CPU and memory need the Kubernetes Metrics Server. Restarts, status, and events work without it."
            )
        }
        if signal == .events, !snapshot.eventsAvailable {
            return ("Events are not available", "This account is not allowed to list events in all namespaces.")
        }
        return nil
    }

    // MARK: Loading

    /// Called once when the window appears. Loads the cluster and keeps it fresh.
    func start() {
        guard loop == nil else { return }
        reload()
    }

    /// Refreshes now and restarts the auto refresh timer.
    func reload() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard let interval = self?.refreshInterval, interval > 0 else { return }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private func reconnect() {
        snapshot = nil
        zoomID = nil
        selectedPodID = nil
        refreshError = nil
        phase = .loading
        rebuild()
        Task {
            await source.disconnect()
            reload()
        }
    }

    private func refresh() async {
        generation += 1
        let current = generation
        isRefreshing = true
        defer { if current == generation { isRefreshing = false } }

        if demo {
            contexts = ["demo"]
            activeContext = "demo"
            show(DemoCluster.snapshot())
            return
        }
        do {
            let available = try source.contexts(kubeconfigPath: kubeconfigPath, preferring: context)
            contexts = available.names
            activeContext = available.selected
            let fresh = try await source.snapshot(
                kubeconfigPath: kubeconfigPath, context: context, window: thresholds.window)
            // A context switch may have started a newer refresh while this one was in flight.
            guard current == generation else { return }
            show(fresh)
        } catch {
            guard current == generation, !Task.isCancelled else { return }
            let title = (error as? LocalizedError)?.errorDescription ?? "The cluster could not be loaded"
            let detail = (error as? LocalizedError)?.recoverySuggestion ?? error.localizedDescription
            if snapshot != nil {
                // Keep the last good map on screen and say it is stale.
                refreshError = "\(title). \(detail)"
            } else {
                phase = .failed(title: title, detail: detail, symbol: Self.symbol(for: error))
            }
        }
    }

    private func show(_ fresh: ClusterSnapshot) {
        snapshot = fresh
        refreshError = nil
        phase = .loaded
        rebuild()
        if let selectedPodID, fresh.pod(selectedPodID) == nil { self.selectedPodID = nil }
        if let zoomID, tree.find(zoomID) == nil { self.zoomID = nil }
    }

    private func rebuild() {
        guard let snapshot else {
            tree = TreeNode(id: "cluster", name: "Cluster", kind: .cluster, size: 0, score: nil, podCount: 0)
            return
        }
        tree = TreeBuilder.build(
            snapshot, signal: signal, grouping: grouping, thresholds: thresholds, hideSystem: hideSystem,
            name: activeContext ?? "Cluster")
    }

    private static func symbol(for error: Error) -> String {
        switch error as? KubeError {
        case .configNotFound, .configInvalid, .noContext, .contextNotFound, .clusterNotFound, .userNotFound, .invalidServer:
            "doc.questionmark"
        case .execMissing, .execFailed, .identity, .http(status: 401, _), .http(status: 403, _):
            "lock.trianglebadge.exclamationmark"
        default:
            "wifi.exclamationmark"
        }
    }

    // MARK: Navigation

    func zoom(into id: String?) {
        zoomID = (id == tree.id) ? nil : id
    }

    /// One level up. Deselects first when a pod is selected.
    func zoomOut() {
        if selectedPodID != nil {
            selectedPodID = nil
        } else if breadcrumb.count > 1 {
            zoom(into: breadcrumb[breadcrumb.count - 2].id)
        }
    }

    func select(pod id: String?) {
        selectedPodID = (id == selectedPodID) ? nil : id
        if selectedPodID != nil { showInspector = true }
    }

    // MARK: Persistence

    private func store(_ value: Any?, _ key: String) {
        defaults.set(value, forKey: key)
    }

    private func storeThresholds() {
        defaults.set(thresholds.warning, forKey: "warningThreshold")
        defaults.set(thresholds.critical, forKey: "criticalThreshold")
        defaults.set(thresholds.restarts, forKey: "restartThreshold")
        defaults.set(thresholds.events, forKey: "eventThreshold")
    }
}

extension Signal {
    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .restarts: "arrow.counterclockwise"
        case .status: "heart.text.square"
        case .events: "exclamationmark.triangle"
        }
    }

    /// One line for the inspector: what the color and the tile size mean.
    var explanation: String {
        switch self {
        case .cpu: "Color is CPU usage against the pod's limit, or its request when no limit is set. Size is CPU usage."
        case .memory: "Color is memory usage against the pod's limit, or its request when no limit is set. Size is memory usage."
        case .restarts: "Color is the restart count of pods that restarted in the last hour. Older restarts stay in the label."
        case .status: "Color is the pod's state: running and ready, pending or not ready, or failing."
        case .events: "Color is the number of Warning events for the pod in the last hour."
        }
    }
}

extension Grouping {
    var symbol: String {
        switch self {
        case .namespace: "square.grid.2x2"
        case .node: "server.rack"
        }
    }
}
