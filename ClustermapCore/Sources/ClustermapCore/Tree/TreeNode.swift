import Foundation

public struct TreeNode: Identifiable, Sendable {
    public enum Kind: Sendable, Equatable {
        case cluster, namespace, node, pod
        case workload(String)

        public var title: String {
            switch self {
            case .cluster: "Cluster"
            case .namespace: "Namespace"
            case .node: "Node"
            case .pod: "Pod"
            case .workload(let kind): kind
            }
        }
    }

    /// Stable across refreshes, so zoom and selection survive new data.
    public let id: String
    public let name: String
    public let kind: Kind
    /// Tile area. A group is the sum of its children.
    public let size: Double
    /// 0...1 for the active signal. A group takes its worst child. Nil means no data.
    public let score: Double?
    public let children: [TreeNode]
    /// Set on leaves only.
    public let podID: String?
    /// Value text for the active signal (leaves) or a pod count (groups).
    public let detail: String
    public let podCount: Int
    public let warningCount: Int
    public let criticalCount: Int

    public var isLeaf: Bool { podID != nil }

    public init(
        id: String, name: String, kind: Kind, size: Double, score: Double?, children: [TreeNode] = [],
        podID: String? = nil, detail: String = "", podCount: Int = 1, warningCount: Int = 0,
        criticalCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.size = size
        self.score = score
        self.children = children
        self.podID = podID
        self.detail = detail
        self.podCount = podCount
        self.warningCount = warningCount
        self.criticalCount = criticalCount
    }

    /// Nodes from this one down to `id`, both ends included.
    public func path(to id: String) -> [TreeNode]? {
        if self.id == id { return [self] }
        for child in children {
            if let rest = child.path(to: id) { return [self] + rest }
        }
        return nil
    }

    public func find(_ id: String) -> TreeNode? {
        path(to: id)?.last
    }

    public func leaf(forPod podID: String) -> TreeNode? {
        if self.podID == podID { return self }
        for child in children {
            if let found = child.leaf(forPod: podID) { return found }
        }
        return nil
    }

    /// Every pod tile below this node.
    public func leaves() -> [TreeNode] {
        isLeaf ? [self] : children.flatMap { $0.leaves() }
    }
}
