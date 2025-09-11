//
//  TreeBuilder.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import Foundation
import SwiftUI

struct TreeBuilder {
    static func build(snapshot: ClusterSnapshot, metric: SizingMetric)
        -> TreeNode
    {
        return buildByResourceType(snapshot: snapshot, metric: metric)
    }

    private static func buildByResourceType(snapshot: ClusterSnapshot, metric: SizingMetric)
        -> TreeNode
    {
        let namespaceNodes = snapshot.namespaces.compactMap { namespace in
            createNamespaceNodeByResourceType(
                namespace: namespace,
                snapshot: snapshot,
                metric: metric
            )
        }

        return createTreeNode(name: "Cluster", children: namespaceNodes)
    }

    private static func createNamespaceNodeByResourceType(
        namespace: KubeNamespace,
        snapshot: ClusterSnapshot,
        metric: SizingMetric
    ) -> TreeNode? {
        let deployments = snapshot.deploymentsByNS[namespace.metadata.name] ?? []
        let pods = snapshot.podsByNS[namespace.metadata.name] ?? []

        let deploymentNodes = deployments.compactMap { deployment in
            createDeploymentNodeWithPods(
                deployment: deployment, pods: pods, snapshot: snapshot, metric: metric)
        }

        guard !deploymentNodes.isEmpty else { return nil }
        return createTreeNode(name: namespace.metadata.name, children: deploymentNodes)
    }

    private static func createDeploymentNodeWithPods(
        deployment: KubeDeployment,
        pods: [KubePod],
        snapshot: ClusterSnapshot,
        metric: SizingMetric
    ) -> TreeNode? {
        let ownedPods = findOwnedPods(for: deployment, in: pods)

        let podNodes = ownedPods.map { pod in
            createLeafNode(
                name: pod.metadata.name,
                value: calculateMetricValue(for: pod, in: snapshot, metric: metric)
            )
        }

        guard !podNodes.isEmpty else { return nil }
        return createTreeNode(name: deployment.metadata.name, children: podNodes)
    }

    private static func createTreeNode(name: String, children: [TreeNode]) -> TreeNode {
        let totalValue = children.reduce(0) { $0 + $1.value }
        return TreeNode(name: name, value: totalValue, children: children)
    }

    private static func createLeafNode(name: String, value: Double) -> TreeNode {
        TreeNode(name: name, value: value, children: [])
    }

    private static func findOwnedPods(for deployment: KubeDeployment, in pods: [KubePod])
        -> [KubePod]
    {
        pods.filter { pod in
            let ownerNames = pod.metadata.ownerReferences?.map { $0.name } ?? []
            return ownerNames.contains { $0.starts(with: deployment.metadata.name) }
        }
    }

    private static func calculateMetricValue(
        for pod: KubePod, in snapshot: ClusterSnapshot, metric: SizingMetric
    ) -> Double {
        switch metric {
        case .count:
            return 1.0
        case .cpu, .memory:
            guard let podMetrics = snapshot.metricsByNS[pod.metadata.namespace ?? ""]?
                .first(where: { $0.metadata.name == pod.metadata.name })
            else {
                return 0.0
            }
            return ResourceCalculator.totalUsage(for: podMetrics, metric: metric)
        }
    }
}

private struct ResourceCalculator {
    static func totalUsage(for metrics: PodMetrics, metric: SizingMetric) -> Double {
        metrics.containers.reduce(0) { total, container in
            let value: Double
            switch metric {
            case .cpu:
                value = parseCpuUsage(container.usage.cpu) ?? 0
            case .memory:
                value = parseMemoryUsage(container.usage.memory) ?? 0
            case .count:
                value = 1.0
            }
            return total + value
        }
    }

    private static func parseCpuUsage(_ value: String?) -> Double? {
        guard var value = value else { return nil }

        if value.hasSuffix("n") {
            value.removeLast()
            return (Double(value) ?? 0) / 1_000_000_000.0
        }
        if value.hasSuffix("u") {
            value.removeLast()
            return (Double(value) ?? 0) / 1_000_000.0
        }
        if value.hasSuffix("m") {
            value.removeLast()
            return (Double(value) ?? 0) / 1000.0
        }
        return Double(value)
    }

    private static func parseMemoryUsage(_ value: String?) -> Double? {
        guard let value = value else { return nil }

        let units: [(String, Double)] = [
            ("Ki", 1024), ("Mi", 1024 * 1024), ("Gi", 1024 * 1024 * 1024),
            ("K", 1000), ("M", 1_000_000), ("G", 1_000_000_000),
        ]

        for (unit, multiplier) in units {
            if value.hasSuffix(unit),
                let number = Double(value.dropLast(unit.count))
            {
                return number * multiplier
            }
        }

        return Double(value)
    }
}
