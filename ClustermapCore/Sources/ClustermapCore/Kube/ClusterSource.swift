import Foundation

/// Loads snapshots for one kubeconfig context at a time and keeps the connection between refreshes.
public actor ClusterSource {
    private var cacheKey: String?
    private var client: KubeClient?

    public init() {}

    /// Context names in the kubeconfig and the one that would be used.
    public nonisolated func contexts(kubeconfigPath: String, preferring preferred: String?) throws -> (names: [String], selected: String?) {
        let config = try KubeConfig.load(path: kubeconfigPath)
        return (config.contextNames, config.contextName(preferring: preferred))
    }

    public func snapshot(
        kubeconfigPath: String, context preferred: String?, window: TimeInterval = 3600, now: Date = Date()
    ) async throws -> ClusterSnapshot {
        let client = try await connect(kubeconfigPath: kubeconfigPath, context: preferred, now: now)

        // Pods are required. Metrics and events are optional: a cluster may lack the Metrics Server,
        // and a restricted account may not list events.
        async let pods = client.listPods()
        async let metrics = try? client.listPodMetrics()
        async let events = try? client.listWarningEvents()

        do {
            return ClusterSnapshot.build(
                pods: try await pods, metrics: await metrics, events: await events, window: window, now: now)
        } catch KubeError.http(status: 401, let message) {
            // The token was rejected. Drop the connection so the next refresh asks the plugin again.
            disconnect()
            throw KubeError.http(status: 401, message: message)
        }
    }

    public func disconnect() {
        cacheKey = nil
        client = nil
    }

    private func connect(kubeconfigPath: String, context preferred: String?, now: Date) async throws -> KubeClient {
        let config = try KubeConfig.load(path: kubeconfigPath)
        guard let context = config.contextName(preferring: preferred) else { throw KubeError.noContext }

        // Editing the kubeconfig, switching context, or a token close to expiry all force a new connection.
        let path = KubeConfig.expand(kubeconfigPath)
        let modified = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? .distantPast
        let key = "\(path)|\(context)|\(modified.timeIntervalSince1970)"
        if key == cacheKey, let client, client.expiresAt.map({ $0 > now.addingTimeInterval(60) }) ?? true {
            return client
        }

        let credentials = try await CredentialResolver.resolve(config, context: context, configPath: kubeconfigPath)
        let fresh = try await KubeClient.make(credentials)
        cacheKey = key
        client = fresh
        return fresh
    }
}
