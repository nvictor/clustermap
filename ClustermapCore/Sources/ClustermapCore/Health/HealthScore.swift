import Foundation

/// Turns a pod and a signal into a 0...1 score (0 healthy, 0.5 warning, 1 critical), a tile size, and a label.
public enum Health {
    /// Nil means "no data": no metrics sample, or no limit and no request to compare against.
    public static func score(_ pod: PodInfo, _ signal: Signal, _ thresholds: Thresholds = Thresholds()) -> Double? {
        switch signal {
        case .cpu:
            return pod.cpu.ratio.map { scaled($0, thresholds) }
        case .memory:
            return pod.memory.ratio.map { scaled($0, thresholds) }
        case .restarts:
            return counted(pod.recentRestarts, limit: thresholds.restarts)
        case .status:
            return pod.state.severity.score
        case .events:
            return counted(pod.recentEvents, limit: thresholds.events)
        }
    }

    /// Maps a usage ratio so the warning threshold lands on 0.5 and the critical threshold on 1.
    public static func scaled(_ ratio: Double, _ thresholds: Thresholds) -> Double {
        let warning = max(0.01, thresholds.warning)
        let critical = max(warning + 0.01, thresholds.critical)
        if ratio <= 0 { return 0 }
        if ratio < warning { return 0.5 * ratio / warning }
        if ratio < critical { return 0.5 + 0.5 * (ratio - warning) / (critical - warning) }
        return 1
    }

    /// Zero is healthy. One occurrence is already a warning. `limit` occurrences are critical.
    public static func counted(_ count: Int, limit: Int) -> Double {
        guard count > 0 else { return 0 }
        return min(1, 0.5 + 0.5 * Double(count) / Double(max(1, limit)))
    }

    /// Raw footprint for the tile. Nil for signals where every pod is the same size.
    public static func size(_ pod: PodInfo, _ signal: Signal) -> Double? {
        switch signal {
        case .cpu: pod.cpu.usage ?? 0
        case .memory: pod.memory.usage ?? 0
        case .restarts, .status, .events: nil
        }
    }

    public static func label(_ pod: PodInfo, _ signal: Signal) -> String {
        switch signal {
        case .cpu: resourceLabel(pod.cpu, format: Format.cpu)
        case .memory: resourceLabel(pod.memory, format: Format.bytes)
        case .restarts: Format.count(pod.restarts, "restart")
        case .status: pod.state.label
        case .events: Format.count(pod.recentEvents, "warning")
        }
    }

    public static func resourceLabel(_ use: ResourceUse, format: (Double) -> String) -> String {
        guard let usage = use.usage else { return "no metrics" }
        guard let ratio = use.ratio else { return "\(format(usage)), no limit" }
        return "\(format(usage)), \(Format.percent(ratio)) of \(use.basis.rawValue)"
    }
}
