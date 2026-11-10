import Foundation

public struct Workload: Sendable, Hashable {
    public let kind: String
    public let name: String

    public init(kind: String, name: String) {
        self.kind = kind
        self.name = name
    }

    /// Bare pods and static pods have no controller. Their name is a group label, not an object.
    public var isStandalone: Bool { kind == "Pod" || kind == "Node" }

    /// "Deployment api", or just "Bare pods".
    public var title: String { isStandalone ? name : "\(kind) \(name)" }

    /// The controller that owns a pod, read from its owner references.
    public static func resolve(_ meta: ObjectMeta) -> Workload {
        let owners = meta.ownerReferences ?? []
        guard let owner = owners.first(where: { $0.controller == true }) ?? owners.first else {
            return Workload(kind: "Pod", name: "Bare pods")
        }
        switch owner.kind {
        case "ReplicaSet":
            // A Deployment names its ReplicaSets <deployment>-<pod-template-hash>.
            if let hash = meta.labels?["pod-template-hash"], owner.name.hasSuffix("-" + hash),
                owner.name.count > hash.count + 1
            {
                return Workload(kind: "Deployment", name: String(owner.name.dropLast(hash.count + 1)))
            }
            return Workload(kind: "ReplicaSet", name: owner.name)
        case "Job":
            // A CronJob names its Jobs <cronjob>-<scheduled time in minutes>.
            if let range = owner.name.range(of: #"-\d{8,}$"#, options: .regularExpression) {
                return Workload(kind: "CronJob", name: String(owner.name[..<range.lowerBound]))
            }
            return Workload(kind: "Job", name: owner.name)
        case "Node":
            return Workload(kind: "Node", name: "Static pods")
        default:
            return Workload(kind: owner.kind, name: owner.name)
        }
    }
}

public enum ResourceBasis: String, Sendable, Hashable {
    case limit, request, none
}

public struct ResourceUse: Sendable, Hashable {
    /// Cores or bytes. Nil when the Metrics Server has no sample for the pod.
    public let usage: Double?
    /// The limit, or the request when no limit is set.
    public let bound: Double?
    public let basis: ResourceBasis

    public init(usage: Double?, bound: Double?, basis: ResourceBasis) {
        self.usage = usage
        self.bound = bound
        self.basis = basis
    }

    public var ratio: Double? {
        guard let usage, let bound, bound > 0 else { return nil }
        return usage / bound
    }
}

public struct PodState: Sendable, Hashable {
    public let label: String
    public let severity: Severity

    public init(_ label: String, _ severity: Severity) {
        self.label = label
        self.severity = severity
    }
}

public struct ContainerInfo: Sendable, Hashable, Identifiable {
    public let name: String
    public let ready: Bool
    public let restarts: Int
    public let state: String

    public var id: String { name }
}

public struct EventInfo: Sendable, Hashable, Identifiable {
    public let id: String
    public let reason: String
    public let message: String
    public let count: Int
    public let last: Date?
}

public struct PodInfo: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let namespace: String
    public let node: String?
    public let workload: Workload
    public let created: Date?
    public let cpu: ResourceUse
    public let memory: ResourceUse
    public let state: PodState
    /// Lifetime restarts across all containers.
    public let restarts: Int
    /// Lifetime restarts, counted only when the last one falls inside the window.
    public let recentRestarts: Int
    public let lastRestart: Date?
    public let lastRestartReason: String?
    public let containers: [ContainerInfo]
    /// Warning events, newest first.
    public let events: [EventInfo]
    /// Occurrences of Warning events inside the window.
    public let recentEvents: Int
}

public struct ClusterSnapshot: Sendable {
    public let pods: [PodInfo]
    public let metricsAvailable: Bool
    public let eventsAvailable: Bool
    public let fetchedAt: Date

    public init(pods: [PodInfo], metricsAvailable: Bool, eventsAvailable: Bool, fetchedAt: Date) {
        self.pods = pods
        self.metricsAvailable = metricsAvailable
        self.eventsAvailable = eventsAvailable
        self.fetchedAt = fetchedAt
    }

    public func pod(_ id: String?) -> PodInfo? {
        guard let id else { return nil }
        return pods.first { $0.id == id }
    }

    /// `metrics` and `events` are nil when their API call failed.
    public static func build(
        pods: [Pod], metrics: [PodMetrics]?, events: [Event]?,
        window: TimeInterval = 3600, now: Date = Date()
    ) -> ClusterSnapshot {
        var usageByPod: [String: (cpu: Double, memory: Double)] = [:]
        for item in metrics ?? [] {
            var cpu = 0.0
            var memory = 0.0
            for container in item.containers ?? [] {
                cpu += Quantity.parse(container.usage?["cpu"]) ?? 0
                memory += Quantity.parse(container.usage?["memory"]) ?? 0
            }
            usageByPod[key(item.metadata.namespace, item.metadata.name)] = (cpu, memory)
        }

        var eventsByPod: [String: [EventInfo]] = [:]
        for (index, event) in (events ?? []).enumerated() {
            guard let object = event.involvedObject, object.kind == "Pod", let name = object.name else { continue }
            let last =
                KubeDate.parse(event.lastTimestamp) ?? KubeDate.parse(event.series?.lastObservedTime)
                ?? KubeDate.parse(event.eventTime) ?? KubeDate.parse(event.firstTimestamp)
                ?? KubeDate.parse(event.metadata.creationTimestamp)
            let info = EventInfo(
                id: "\(event.metadata.namespace ?? "")/\(event.metadata.name)#\(index)",
                reason: event.reason ?? "Warning",
                message: (event.message ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                count: max(1, event.count ?? event.series?.count ?? 1),
                last: last
            )
            eventsByPod[key(object.namespace ?? event.metadata.namespace, name), default: []].append(info)
        }

        let cutoff = now.addingTimeInterval(-window)
        let infos = pods.map { pod -> PodInfo in
            let id = key(pod.metadata.namespace, pod.metadata.name)
            let usage = usageByPod[id]
            let statuses = (pod.status?.initContainerStatuses ?? []) + (pod.status?.containerStatuses ?? [])
            let state = podState(pod, cutoff: cutoff)

            let restarts = statuses.reduce(0) { $0 + ($1.restartCount ?? 0) }
            var lastRestart: Date?
            var lastReason: String?
            for status in statuses {
                guard let terminated = status.lastState?.terminated,
                    let finished = KubeDate.parse(terminated.finishedAt)
                else { continue }
                if lastRestart == nil || finished > lastRestart! {
                    lastRestart = finished
                    lastReason = terminated.reason
                }
            }
            // The API keeps a lifetime count and the time of the last restart, nothing in between.
            let restarting = state.label.hasSuffix("CrashLoopBackOff") || (lastRestart.map { $0 >= cutoff } ?? false)
            let podEvents = (eventsByPod[id] ?? []).sorted { ($0.last ?? .distantPast) > ($1.last ?? .distantPast) }

            return PodInfo(
                id: id,
                name: pod.metadata.name,
                namespace: pod.metadata.namespace ?? "default",
                node: pod.spec?.nodeName,
                workload: Workload.resolve(pod.metadata),
                created: KubeDate.parse(pod.metadata.creationTimestamp),
                cpu: resourceUse("cpu", usage: usage?.cpu, containers: pod.spec?.containers ?? []),
                memory: resourceUse("memory", usage: usage?.memory, containers: pod.spec?.containers ?? []),
                state: state,
                restarts: restarts,
                recentRestarts: restarting ? restarts : 0,
                lastRestart: lastRestart,
                lastRestartReason: lastReason,
                containers: (pod.status?.containerStatuses ?? []).map {
                    ContainerInfo(
                        name: $0.name, ready: $0.ready ?? false, restarts: $0.restartCount ?? 0,
                        state: containerLabel($0.state))
                },
                events: podEvents,
                recentEvents: podEvents.reduce(0) { $0 + (($1.last ?? now) >= cutoff ? $1.count : 0) }
            )
        }

        return ClusterSnapshot(
            pods: infos.sorted { $0.id < $1.id },
            metricsAvailable: metrics != nil,
            eventsAvailable: events != nil,
            fetchedAt: now
        )
    }

    private static func key(_ namespace: String?, _ name: String) -> String {
        "\(namespace ?? "default")/\(name)"
    }

    private static func resourceUse(_ resource: String, usage: Double?, containers: [ContainerSpec]) -> ResourceUse {
        let limits = containers.compactMap { Quantity.parse($0.resources?.limits?[resource]) }
        if !limits.isEmpty {
            return ResourceUse(usage: usage, bound: limits.reduce(0, +), basis: .limit)
        }
        let requests = containers.compactMap { Quantity.parse($0.resources?.requests?[resource]) }
        if !requests.isEmpty {
            return ResourceUse(usage: usage, bound: requests.reduce(0, +), basis: .request)
        }
        return ResourceUse(usage: usage, bound: nil, basis: .none)
    }

    private static let failingReasons: Set<String> = [
        "CrashLoopBackOff", "ImagePullBackOff", "ErrImagePull", "InvalidImageName",
        "CreateContainerConfigError", "CreateContainerError", "RunContainerError",
    ]

    static func podState(_ pod: Pod, cutoff: Date) -> PodState {
        let phase = pod.status?.phase ?? "Unknown"
        if phase == "Succeeded" { return PodState("Completed", .ok) }
        if phase == "Failed" { return PodState(pod.status?.reason ?? "Failed", .critical) }

        for status in pod.status?.initContainerStatuses ?? [] {
            if let reason = status.state?.waiting?.reason, failingReasons.contains(reason) {
                return PodState("Init:" + reason, .critical)
            }
        }
        let statuses = pod.status?.containerStatuses ?? []
        for status in statuses {
            if let reason = status.state?.waiting?.reason, failingReasons.contains(reason) {
                return PodState(reason, .critical)
            }
        }
        for status in statuses {
            if let terminated = status.state?.terminated, (terminated.exitCode ?? 0) != 0 {
                return PodState(terminated.reason ?? "Error", .critical)
            }
            if let last = status.lastState?.terminated, last.reason == "OOMKilled",
                let finished = KubeDate.parse(last.finishedAt), finished >= cutoff
            {
                return PodState("OOMKilled", .critical)
            }
        }

        if pod.metadata.deletionTimestamp != nil { return PodState("Terminating", .warning) }
        if phase == "Pending" {
            let waiting = (pod.status?.initContainerStatuses ?? []) + statuses
            return PodState(waiting.compactMap { $0.state?.waiting?.reason }.first ?? "Pending", .warning)
        }
        if phase == "Running" {
            return statuses.allSatisfy({ $0.ready == true }) ? PodState("Running", .ok) : PodState("NotReady", .warning)
        }
        return PodState(phase, .warning)
    }

    private static func containerLabel(_ state: ContainerState?) -> String {
        if let waiting = state?.waiting { return waiting.reason ?? "Waiting" }
        if let terminated = state?.terminated { return terminated.reason ?? "Terminated" }
        if state?.running != nil { return "Running" }
        return "Unknown"
    }
}
