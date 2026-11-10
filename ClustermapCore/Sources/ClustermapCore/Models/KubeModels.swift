import Foundation

// Only the fields Clustermap reads. Everything except a name is optional, since the API omits empty values.

public struct OwnerReference: Codable, Sendable, Hashable {
    public var kind: String
    public var name: String
    public var controller: Bool?

    public init(kind: String, name: String, controller: Bool? = true) {
        self.kind = kind
        self.name = name
        self.controller = controller
    }
}

public struct ObjectMeta: Codable, Sendable, Hashable {
    public var name: String
    public var namespace: String?
    public var labels: [String: String]?
    public var ownerReferences: [OwnerReference]?
    public var creationTimestamp: String?
    public var deletionTimestamp: String?

    public init(
        name: String, namespace: String? = nil, labels: [String: String]? = nil,
        ownerReferences: [OwnerReference]? = nil, creationTimestamp: String? = nil,
        deletionTimestamp: String? = nil
    ) {
        self.name = name
        self.namespace = namespace
        self.labels = labels
        self.ownerReferences = ownerReferences
        self.creationTimestamp = creationTimestamp
        self.deletionTimestamp = deletionTimestamp
    }
}

public struct ResourceRequirements: Codable, Sendable, Hashable {
    public var requests: [String: String]?
    public var limits: [String: String]?

    public init(requests: [String: String]? = nil, limits: [String: String]? = nil) {
        self.requests = requests
        self.limits = limits
    }
}

public struct ContainerSpec: Codable, Sendable, Hashable {
    public var name: String
    public var resources: ResourceRequirements?

    public init(name: String, resources: ResourceRequirements? = nil) {
        self.name = name
        self.resources = resources
    }
}

public struct PodSpec: Codable, Sendable, Hashable {
    public var nodeName: String?
    public var containers: [ContainerSpec]?

    public init(nodeName: String? = nil, containers: [ContainerSpec]? = nil) {
        self.nodeName = nodeName
        self.containers = containers
    }
}

public struct ContainerState: Codable, Sendable, Hashable {
    public struct Waiting: Codable, Sendable, Hashable {
        public var reason: String?
        public var message: String?
        public init(reason: String? = nil, message: String? = nil) {
            self.reason = reason
            self.message = message
        }
    }
    public struct Running: Codable, Sendable, Hashable {
        public var startedAt: String?
        public init(startedAt: String? = nil) { self.startedAt = startedAt }
    }
    public struct Terminated: Codable, Sendable, Hashable {
        public var reason: String?
        public var exitCode: Int?
        public var finishedAt: String?
        public init(reason: String? = nil, exitCode: Int? = nil, finishedAt: String? = nil) {
            self.reason = reason
            self.exitCode = exitCode
            self.finishedAt = finishedAt
        }
    }

    public var waiting: Waiting?
    public var running: Running?
    public var terminated: Terminated?

    public init(waiting: Waiting? = nil, running: Running? = nil, terminated: Terminated? = nil) {
        self.waiting = waiting
        self.running = running
        self.terminated = terminated
    }
}

public struct ContainerStatus: Codable, Sendable, Hashable {
    public var name: String
    public var ready: Bool?
    public var restartCount: Int?
    public var state: ContainerState?
    public var lastState: ContainerState?

    public init(
        name: String, ready: Bool? = true, restartCount: Int? = 0,
        state: ContainerState? = nil, lastState: ContainerState? = nil
    ) {
        self.name = name
        self.ready = ready
        self.restartCount = restartCount
        self.state = state
        self.lastState = lastState
    }
}

public struct PodStatus: Codable, Sendable, Hashable {
    public var phase: String?
    public var reason: String?
    public var containerStatuses: [ContainerStatus]?
    public var initContainerStatuses: [ContainerStatus]?

    public init(
        phase: String? = nil, reason: String? = nil,
        containerStatuses: [ContainerStatus]? = nil,
        initContainerStatuses: [ContainerStatus]? = nil
    ) {
        self.phase = phase
        self.reason = reason
        self.containerStatuses = containerStatuses
        self.initContainerStatuses = initContainerStatuses
    }
}

public struct Pod: Codable, Sendable, Hashable {
    public var metadata: ObjectMeta
    public var spec: PodSpec?
    public var status: PodStatus?

    public init(metadata: ObjectMeta, spec: PodSpec? = nil, status: PodStatus? = nil) {
        self.metadata = metadata
        self.spec = spec
        self.status = status
    }
}

public struct ContainerMetrics: Codable, Sendable, Hashable {
    public var name: String
    public var usage: [String: String]?

    public init(name: String, usage: [String: String]? = nil) {
        self.name = name
        self.usage = usage
    }
}

public struct PodMetrics: Codable, Sendable, Hashable {
    public var metadata: ObjectMeta
    public var containers: [ContainerMetrics]?

    public init(metadata: ObjectMeta, containers: [ContainerMetrics]? = nil) {
        self.metadata = metadata
        self.containers = containers
    }
}

public struct ObjectReference: Codable, Sendable, Hashable {
    public var kind: String?
    public var namespace: String?
    public var name: String?

    public init(kind: String? = nil, namespace: String? = nil, name: String? = nil) {
        self.kind = kind
        self.namespace = namespace
        self.name = name
    }
}

public struct Event: Codable, Sendable, Hashable {
    public struct Series: Codable, Sendable, Hashable {
        public var count: Int?
        public var lastObservedTime: String?
    }

    public var metadata: ObjectMeta
    public var involvedObject: ObjectReference?
    public var type: String?
    public var reason: String?
    public var message: String?
    public var count: Int?
    public var firstTimestamp: String?
    public var lastTimestamp: String?
    public var eventTime: String?
    public var series: Series?

    public init(
        metadata: ObjectMeta, involvedObject: ObjectReference? = nil, type: String? = "Warning",
        reason: String? = nil, message: String? = nil, count: Int? = nil,
        firstTimestamp: String? = nil, lastTimestamp: String? = nil, eventTime: String? = nil,
        series: Series? = nil
    ) {
        self.metadata = metadata
        self.involvedObject = involvedObject
        self.type = type
        self.reason = reason
        self.message = message
        self.count = count
        self.firstTimestamp = firstTimestamp
        self.lastTimestamp = lastTimestamp
        self.eventTime = eventTime
        self.series = series
    }
}

public enum KubeDate {
    /// Kubernetes writes RFC 3339 with or without fractional seconds (`eventTime` uses microseconds).
    public static func parse(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        if let date = try? Date(string, strategy: .iso8601) { return date }
        return try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }

    public static func string(_ date: Date) -> String {
        date.formatted(.iso8601)
    }
}
