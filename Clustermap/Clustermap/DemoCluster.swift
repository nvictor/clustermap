import ClustermapCore
import Foundation

/// A made-up cluster for screenshots and UI work without a real one. Launch with `--demo`.
enum DemoCluster {
    static func snapshot(now: Date = Date()) -> ClusterSnapshot {
        var random = Generator(state: 42)
        var pods: [Pod] = []
        var metrics: [PodMetrics] = []
        var events: [Event] = []
        let nodes = ["node-a", "node-b", "node-c", "node-d"]

        func add(
            _ namespace: String, _ kind: String, _ workload: String, replicas: Int, cpu: ClosedRange<Double>,
            memory: ClosedRange<Double>, cpuLimit: Double? = 0.5, memoryLimit: Double? = 512, trouble: String? = nil
        ) {
            for index in 0..<replicas {
                let hash = "7c9d8f6b4"
                let name = kind == "StatefulSet" ? "\(workload)-\(index)" : "\(workload)-\(hash)-\(suffix(&random))"
                let owner =
                    kind == "Deployment"
                    ? OwnerReference(kind: "ReplicaSet", name: "\(workload)-\(hash)") : OwnerReference(kind: kind, name: workload)
                var limits: [String: String] = [:]
                if let cpuLimit { limits["cpu"] = "\(Int(cpuLimit * 1000))m" }
                if let memoryLimit { limits["memory"] = "\(Int(memoryLimit))Mi" }

                var status = ContainerStatus(name: workload, state: ContainerState(running: .init()))
                var phase = "Running"
                let broken = trouble != nil && index == 0
                switch broken ? trouble : nil {
                case "crash":
                    status = ContainerStatus(
                        name: workload, ready: false, restartCount: 14,
                        state: ContainerState(waiting: .init(reason: "CrashLoopBackOff")),
                        lastState: ContainerState(terminated: .init(reason: "Error", exitCode: 1, finishedAt: KubeDate.string(now.addingTimeInterval(-90)))))
                    events.append(event(namespace, name, "BackOff", "Back-off restarting failed container \(workload)", 23, now.addingTimeInterval(-60)))
                case "image":
                    phase = "Pending"
                    status = ContainerStatus(name: workload, ready: false, state: ContainerState(waiting: .init(reason: "ImagePullBackOff")))
                    events.append(event(namespace, name, "Failed", "Failed to pull image \"registry.local/\(workload):v9\": not found", 6, now.addingTimeInterval(-200)))
                case "oom":
                    status = ContainerStatus(
                        name: workload, restartCount: 3, state: ContainerState(running: .init()),
                        lastState: ContainerState(terminated: .init(reason: "OOMKilled", exitCode: 137, finishedAt: KubeDate.string(now.addingTimeInterval(-900)))))
                case "pending":
                    phase = "Pending"
                    status = ContainerStatus(name: workload, ready: false, state: nil)
                    events.append(event(namespace, name, "FailedScheduling", "0/4 nodes are available: 4 Insufficient memory.", 2, now.addingTimeInterval(-400)))
                case "probe":
                    status = ContainerStatus(name: workload, ready: false, restartCount: 1, state: ContainerState(running: .init()))
                    events.append(event(namespace, name, "Unhealthy", "Readiness probe failed: HTTP probe failed with statuscode: 503", 4, now.addingTimeInterval(-30)))
                default:
                    break
                }

                pods.append(
                    Pod(
                        metadata: ObjectMeta(
                            name: name, namespace: namespace, labels: ["pod-template-hash": hash], ownerReferences: [owner],
                            creationTimestamp: KubeDate.string(now.addingTimeInterval(-Double(random.next(in: 600...900_000))))),
                        spec: PodSpec(
                            nodeName: phase == "Pending" && trouble == "pending" ? nil : nodes[random.next(in: 0...3)],
                            containers: [ContainerSpec(name: workload, resources: ResourceRequirements(limits: limits.isEmpty ? nil : limits))]),
                        status: PodStatus(phase: phase, containerStatuses: [status])))

                guard phase == "Running" else { continue }
                var cpuUse = random.unit(in: cpu)
                var memoryUse = random.unit(in: memory)
                if broken, trouble == "oom", let memoryLimit { memoryUse = memoryLimit * 0.96 }
                if broken, trouble == "hot", let cpuLimit { cpuUse = cpuLimit * 0.97 }
                metrics.append(
                    PodMetrics(
                        metadata: ObjectMeta(name: name, namespace: namespace),
                        containers: [
                            ContainerMetrics(name: workload, usage: ["cpu": "\(Int(cpuUse * 1_000_000))u", "memory": "\(Int(memoryUse * 1024))Ki"])
                        ]))
            }
        }

        add("shop", "Deployment", "storefront", replicas: 6, cpu: 0.08...0.3, memory: 120...300, trouble: "hot")
        add("shop", "Deployment", "checkout", replicas: 4, cpu: 0.05...0.2, memory: 150...420, trouble: "oom")
        add("shop", "Deployment", "cart", replicas: 3, cpu: 0.02...0.1, memory: 60...140, cpuLimit: 0.25, memoryLimit: 256)
        add("shop", "StatefulSet", "postgres", replicas: 3, cpu: 0.2...0.7, memory: 900...1700, cpuLimit: 1, memoryLimit: 2048)
        add("shop", "StatefulSet", "redis", replicas: 3, cpu: 0.03...0.12, memory: 80...200, cpuLimit: 0.25, memoryLimit: 256)
        add("payments", "Deployment", "ledger", replicas: 4, cpu: 0.1...0.35, memory: 200...380, trouble: "crash")
        add("payments", "Deployment", "fraud-scoring", replicas: 2, cpu: 0.4...0.85, memory: 600...900, cpuLimit: 1, memoryLimit: 1024)
        add("payments", "Deployment", "gateway", replicas: 3, cpu: 0.05...0.18, memory: 90...180, trouble: "probe")
        add("search", "Deployment", "indexer", replicas: 2, cpu: 0.3...0.9, memory: 500...1200, cpuLimit: nil, memoryLimit: nil)
        add("search", "StatefulSet", "opensearch", replicas: 3, cpu: 0.3...0.6, memory: 1500...2600, cpuLimit: 1, memoryLimit: 3072)
        add("search", "Deployment", "query-api", replicas: 4, cpu: 0.05...0.2, memory: 100...240, trouble: "image")
        add("batch", "Job", "nightly-report-29384756", replicas: 2, cpu: 0.2...0.45, memory: 200...400)
        add("batch", "Deployment", "worker", replicas: 5, cpu: 0.1...0.4, memory: 150...350, trouble: "pending")
        add("monitoring", "DaemonSet", "node-exporter", replicas: 4, cpu: 0.01...0.04, memory: 20...45, cpuLimit: 0.1, memoryLimit: 64)
        add("monitoring", "StatefulSet", "prometheus", replicas: 2, cpu: 0.3...0.6, memory: 1200...1900, cpuLimit: 1, memoryLimit: 2048)
        add("monitoring", "Deployment", "grafana", replicas: 1, cpu: 0.02...0.06, memory: 90...140, cpuLimit: 0.25, memoryLimit: 256)
        add("kube-system", "DaemonSet", "kube-proxy", replicas: 4, cpu: 0.005...0.02, memory: 15...30, cpuLimit: nil, memoryLimit: nil)
        add("kube-system", "Deployment", "coredns", replicas: 2, cpu: 0.005...0.03, memory: 18...40, cpuLimit: nil, memoryLimit: 170)
        add("kube-system", "Deployment", "metrics-server", replicas: 1, cpu: 0.01...0.03, memory: 25...50, cpuLimit: nil, memoryLimit: nil)

        return ClusterSnapshot.build(pods: pods, metrics: metrics, events: events, now: now)
    }

    private static func event(_ namespace: String, _ pod: String, _ reason: String, _ message: String, _ count: Int, _ last: Date) -> Event {
        Event(
            metadata: ObjectMeta(name: "\(pod).\(reason)", namespace: namespace),
            involvedObject: ObjectReference(kind: "Pod", namespace: namespace, name: pod),
            reason: reason, message: message, count: count, lastTimestamp: KubeDate.string(last))
    }

    private static func suffix(_ random: inout Generator) -> String {
        let letters = Array("bcdfghjklmnpqrstvwxz2456789")
        return String((0..<5).map { _ in letters[random.next(in: 0...(letters.count - 1))] })
    }

    /// Fixed seed, so the demo looks the same on every launch.
    private struct Generator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state >> 33
        }

        mutating func next(in range: ClosedRange<Int>) -> Int {
            range.lowerBound + Int(next() % UInt64(range.count))
        }

        mutating func unit(in range: ClosedRange<Double>) -> Double {
            range.lowerBound + (range.upperBound - range.lowerBound) * Double(next() % 10_000) / 10_000
        }
    }
}
