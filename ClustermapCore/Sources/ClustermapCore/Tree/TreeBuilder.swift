import Foundation

public enum TreeBuilder {
    public static let systemNamespaces: Set<String> = ["kube-system", "kube-public", "kube-node-lease"]

    /// Idle pods keep this share of the largest pod's area, so they stay visible and clickable.
    static let sizeFloor = 0.02

    public static func build(
        _ snapshot: ClusterSnapshot, signal: Signal, grouping: Grouping,
        thresholds: Thresholds = Thresholds(), hideSystem: Bool = false, name: String = "Cluster"
    ) -> TreeNode {
        let pods = hideSystem ? snapshot.pods.filter { !systemNamespaces.contains($0.namespace) } : snapshot.pods
        let largest = pods.compactMap { Health.size($0, signal) }.max() ?? 0

        func leaf(_ pod: PodInfo, parent: String, name: String) -> TreeNode {
            let raw = Health.size(pod, signal)
            let size = (raw == nil || largest <= 0) ? 1 : max(raw!, largest * sizeFloor)
            let score = Health.score(pod, signal, thresholds)
            let severity = score.map(Severity.init(score:))
            return TreeNode(
                id: "\(parent)/pod:\(pod.id)", name: name, kind: .pod, size: size, score: score,
                podID: pod.id, detail: Health.label(pod, signal),
                warningCount: severity == .warning ? 1 : 0, criticalCount: severity == .critical ? 1 : 0)
        }

        let groups: [TreeNode]
        switch grouping {
        case .namespace:
            groups = Dictionary(grouping: pods, by: \.namespace).map { namespace, members in
                let id = "ns:\(namespace)"
                let workloads = Dictionary(grouping: members, by: \.workload).map { workload, owned in
                    let workloadID = "\(id)/wl:\(workload.kind)/\(workload.name)"
                    return group(
                        id: workloadID, name: workload.name, kind: .workload(workload.kind),
                        children: owned.map { leaf($0, parent: workloadID, name: $0.name) })
                }
                return group(id: id, name: namespace, kind: .namespace, children: workloads)
            }
        case .node:
            groups = Dictionary(grouping: pods, by: { $0.node ?? "" }).map { node, members in
                let id = "node:\(node)"
                return group(
                    id: id, name: node.isEmpty ? "Unscheduled" : node, kind: .node,
                    children: members.map { leaf($0, parent: id, name: $0.name) })
            }
        }
        return group(id: "cluster", name: name, kind: .cluster, children: groups)
    }

    static func group(id: String, name: String, kind: TreeNode.Kind, children: [TreeNode]) -> TreeNode {
        // Largest first for the squarified layout. Name breaks ties so the map does not shuffle on refresh.
        let sorted = children.sorted { $0.size != $1.size ? $0.size > $1.size : $0.name < $1.name }
        let pods = sorted.reduce(0) { $0 + $1.podCount }
        return TreeNode(
            id: id, name: name, kind: kind,
            size: sorted.reduce(0) { $0 + $1.size },
            score: sorted.compactMap(\.score).max(),
            children: sorted,
            detail: Format.count(pods, "pod"),
            podCount: pods,
            warningCount: sorted.reduce(0) { $0 + $1.warningCount },
            criticalCount: sorted.reduce(0) { $0 + $1.criticalCount })
    }
}
