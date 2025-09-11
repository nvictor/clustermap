//
//  ClusterService.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import Foundation

struct ClusterService {
    func fetchTree(from path: String, metric: SizingMetric) async
        -> Result<TreeNode, Error>
    {
        do {
            let snapshot = try await fetchClusterData(from: path)
            let tree = TreeBuilder.build(snapshot: snapshot, metric: metric)
            return .success(tree)
        } catch {
            return .failure(error)
        }
    }

    private func fetchClusterData(from path: String) async throws -> ClusterSnapshot {
        let config = try ConfigLoader.parseKubeConfig(at: path)
        let creds = try await ConfigLoader.makeCredentials(config)
        let client = try Client(creds: creds)

        let namespaces = try await client.listNamespaces()
        await LogService.shared.log(
            "Loaded namespaces: \(namespaces.map(\.metadata.name))", type: .info)

        let (deploymentsByNS, podsByNS, metricsByNS) = try await fetchNamespaceResources(
            for: namespaces,
            using: client
        )

        return ClusterSnapshot(
            namespaces: namespaces,
            deploymentsByNS: deploymentsByNS,
            podsByNS: podsByNS,
            metricsByNS: metricsByNS
        )
    }

    private func fetchNamespaceResources(
        for namespaces: [KubeNamespace],
        using client: Client
    ) async throws -> ([String: [KubeDeployment]], [String: [KubePod]], [String: [PodMetrics]]) {
        var deploymentsByNS = [String: [KubeDeployment]]()
        var podsByNS = [String: [KubePod]]()
        var metricsByNS = [String: [PodMetrics]]()

        try await withThrowingTaskGroup(of: NamespaceResources.self) { group in
            for namespace in namespaces {
                group.addTask {
                    try await fetchResourcesForNamespace(namespace.metadata.name, using: client)
                }
            }

            for try await resources in group {
                deploymentsByNS[resources.name] = resources.deployments
                podsByNS[resources.name] = resources.pods
                metricsByNS[resources.name] = resources.metrics
            }
        }

        return (deploymentsByNS, podsByNS, metricsByNS)
    }

    private func fetchResourcesForNamespace(_ name: String, using client: Client) async throws
        -> NamespaceResources
    {
        async let deployments = client.listDeployments(namespace: name)
        async let pods = client.listPods(namespace: name, selector: nil)

        let metrics: [PodMetrics]
        do {
            metrics = try await client.listPodMetrics(namespace: name)
        } catch {
            await LogService.shared.log(
                "Could not fetch metrics for namespace \(name): \(error.localizedDescription)",
                type: .error)
            metrics = []
        }

        let (d, p) = try await (deployments, pods)
        return NamespaceResources(name: name, deployments: d, pods: p, metrics: metrics)
    }
}

private struct NamespaceResources {
    let name: String
    let deployments: [KubeDeployment]
    let pods: [KubePod]
    let metrics: [PodMetrics]
}
