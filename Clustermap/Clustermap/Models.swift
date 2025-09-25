//
//  Models.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import Foundation

struct TreeNode: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let value: Double
    let children: [TreeNode]
    let maxSubtreeLeafValue: Double
    var isLeaf: Bool { children.isEmpty }
}

struct OwnerReference: Codable, Hashable {
    let apiVersion: String
    let kind: String
    let name: String
    let uid: String
}
struct ObjectMeta: Codable, Hashable {
    let name: String
    let namespace: String?
    let labels: [String: String]?
    let uid: String?
    let ownerReferences: [OwnerReference]?
}
struct KubeNamespace: Codable, Hashable, Identifiable {
    let metadata: ObjectMeta
    var id: String { metadata.name }
}
struct KubeNamespaceList: Codable { let items: [KubeNamespace] }
struct ResourceRequirements: Codable, Hashable {
    let requests: [String: String]?
    let limits: [String: String]?
}
struct ContainerSpec: Codable, Hashable {
    let name: String
    let resources: ResourceRequirements?
}
struct PodSpec: Codable, Hashable { let containers: [ContainerSpec]? }
struct PodStatus: Codable, Hashable { let phase: String? }
struct KubePod: Codable, Hashable, Identifiable {
    let metadata: ObjectMeta
    let spec: PodSpec?
    let status: PodStatus?
    var id: String { metadata.name }
}
struct KubePodList: Codable { let items: [KubePod] }
struct PodTemplate: Codable, Hashable { let spec: PodSpec? }
struct DeploymentSpec: Codable, Hashable {
    let replicas: Int?
    let template: PodTemplate?
}
struct DeploymentStatus: Codable, Hashable { let availableReplicas: Int? }
struct KubeDeployment: Codable, Hashable, Identifiable {
    let metadata: ObjectMeta
    let spec: DeploymentSpec?
    let status: DeploymentStatus?
    var id: String { metadata.name }
}
struct KubeDeploymentList: Codable { let items: [KubeDeployment] }

struct MetricUsage: Codable, Hashable {
    let cpu: String
    let memory: String
}

struct ContainerMetrics: Codable, Hashable {
    let name: String
    let usage: MetricUsage
}

struct PodMetrics: Codable, Hashable {
    let metadata: ObjectMeta
    let timestamp: String
    let window: String
    let containers: [ContainerMetrics]
}

struct PodMetricsList: Codable {
    let items: [PodMetrics]
}

struct ClusterSnapshot {
    let namespaces: [KubeNamespace]
    let deploymentsByNS: [String: [KubeDeployment]]
    let podsByNS: [String: [KubePod]]
    let metricsByNS: [String: [PodMetrics]]

    static func empty() -> ClusterSnapshot {
        .init(namespaces: [], deploymentsByNS: [:], podsByNS: [:], metricsByNS: [:])
    }
}

struct Credentials {
    let server: URL
    let token: String?
    let caData: Data?
    let certData: Data?
    let insecure: Bool
}

enum LogType {
    case info
    case success
    case error
}

struct LogEntry: Identifiable, Hashable {
    let id = UUID()
    let message: String
    let type: LogType
    let timestamp: Date
}
