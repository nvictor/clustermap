import Foundation

public enum Signal: String, CaseIterable, Identifiable, Sendable, Codable {
    case cpu, memory, restarts, status, events

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .restarts: "Restarts"
        case .status: "Status"
        case .events: "Events"
        }
    }

    /// CPU and memory need the Metrics Server.
    public var needsMetrics: Bool { self == .cpu || self == .memory }
}

public enum Grouping: String, CaseIterable, Identifiable, Sendable, Codable {
    case namespace, node

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .namespace: "Namespace"
        case .node: "Node"
        }
    }
}

public enum Severity: Int, Comparable, Sendable, Codable {
    case ok, warning, critical

    public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Scores run 0...1. Warning starts at 0.5, critical at 1.
    public init(score: Double) {
        self = score >= 1 ? .critical : (score >= 0.5 ? .warning : .ok)
    }

    public var score: Double {
        switch self {
        case .ok: 0
        case .warning: 0.5
        case .critical: 1
        }
    }

    public var title: String {
        switch self {
        case .ok: "Healthy"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }
}

public struct Thresholds: Sendable, Equatable, Codable {
    /// Share of the limit (or request) where CPU and memory turn warning, then critical.
    public var warning: Double
    public var critical: Double
    /// Recent restarts that count as critical. Any recent restart is at least a warning.
    public var restarts: Int
    /// Recent Warning events that count as critical. Any recent event is at least a warning.
    public var events: Int
    /// What "recent" means for restarts and events.
    public var window: TimeInterval

    public init(
        warning: Double = 0.7, critical: Double = 0.9, restarts: Int = 5, events: Int = 10,
        window: TimeInterval = 3600
    ) {
        self.warning = warning
        self.critical = critical
        self.restarts = restarts
        self.events = events
        self.window = window
    }
}
