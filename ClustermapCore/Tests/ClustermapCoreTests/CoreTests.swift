import CoreGraphics
import Foundation
import Security
import Testing

@testable import ClustermapCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func ago(_ seconds: TimeInterval) -> String {
    KubeDate.string(now.addingTimeInterval(-seconds))
}

private func pod(
    _ name: String, namespace: String = "shop", node: String? = "node-a", phase: String = "Running",
    owner: OwnerReference? = OwnerReference(kind: "ReplicaSet", name: "api-7d9f8c6b5"),
    labels: [String: String]? = ["pod-template-hash": "7d9f8c6b5"],
    resources: ResourceRequirements? = nil, statuses: [ContainerStatus]? = nil
) -> Pod {
    Pod(
        metadata: ObjectMeta(name: name, namespace: namespace, labels: labels, ownerReferences: owner.map { [$0] }),
        spec: PodSpec(nodeName: node, containers: [ContainerSpec(name: "app", resources: resources)]),
        status: PodStatus(
            phase: phase,
            containerStatuses: statuses ?? [ContainerStatus(name: "app", state: ContainerState(running: .init()))]))
}

private func metrics(_ name: String, namespace: String = "shop", cpu: String, memory: String) -> PodMetrics {
    PodMetrics(
        metadata: ObjectMeta(name: name, namespace: namespace),
        containers: [ContainerMetrics(name: "app", usage: ["cpu": cpu, "memory": memory])])
}

@Suite struct QuantityTests {
    @Test func parsesCPU() {
        #expect(Quantity.parse("250m") == 0.25)
        #expect(Quantity.parse("2") == 2)
        #expect(abs(Quantity.parse("1500n")! - 0.0000015) < 1e-12)
        #expect(abs(Quantity.parse("12345u")! - 0.012345) < 1e-12)
    }

    @Test func parsesMemory() {
        #expect(Quantity.parse("128Mi") == 134_217_728)
        #expect(Quantity.parse("1Gi") == 1_073_741_824)
        #expect(Quantity.parse("1G") == 1_000_000_000)
        #expect(Quantity.parse("64Ki") == 65_536)
        #expect(Quantity.parse("1e3") == 1000)
        #expect(Quantity.parse("1E") == 1e18)
    }

    @Test func rejectsJunk() {
        #expect(Quantity.parse(nil) == nil)
        #expect(Quantity.parse("") == nil)
        #expect(Quantity.parse("lots") == nil)
    }

    @Test func formats() {
        #expect(Format.cpu(0.25) == "250m")
        #expect(Format.cpu(1.5) == "1.5 cores")
        #expect(Format.bytes(134_217_728) == "128 Mi")
        #expect(Format.bytes(1_610_612_736) == "1.5 Gi")
        #expect(Format.percent(0.824) == "82%")
        #expect(Format.age(125) == "2m")
    }
}

@Suite struct WorkloadTests {
    @Test func deploymentFromReplicaSet() {
        let meta = pod("api-7d9f8c6b5-x2x4z").metadata
        #expect(Workload.resolve(meta) == Workload(kind: "Deployment", name: "api"))
    }

    @Test func prefixNamesDoNotCollide() {
        // The old matcher claimed api-server pods for the "api" deployment.
        let meta = ObjectMeta(
            name: "api-server-5c4d-abcde", labels: ["pod-template-hash": "5c4d"],
            ownerReferences: [OwnerReference(kind: "ReplicaSet", name: "api-server-5c4d")])
        #expect(Workload.resolve(meta).name == "api-server")
    }

    @Test func otherControllers() {
        func owned(_ kind: String, _ name: String) -> Workload {
            Workload.resolve(ObjectMeta(name: "p", ownerReferences: [OwnerReference(kind: kind, name: name)]))
        }
        #expect(owned("StatefulSet", "db") == Workload(kind: "StatefulSet", name: "db"))
        #expect(owned("DaemonSet", "agent") == Workload(kind: "DaemonSet", name: "agent"))
        #expect(owned("Job", "migrate") == Workload(kind: "Job", name: "migrate"))
        #expect(owned("Job", "backup-29384756") == Workload(kind: "CronJob", name: "backup"))
        #expect(owned("ReplicaSet", "loose") == Workload(kind: "ReplicaSet", name: "loose"))
        #expect(Workload.resolve(ObjectMeta(name: "p")) == Workload(kind: "Pod", name: "Bare pods"))
    }
}

@Suite struct HealthTests {
    let thresholds = Thresholds()

    @Test func ratioScaling() {
        #expect(Health.scaled(0, thresholds) == 0)
        #expect(abs(Health.scaled(0.35, thresholds) - 0.25) < 1e-9)
        #expect(abs(Health.scaled(0.7, thresholds) - 0.5) < 1e-9)
        #expect(abs(Health.scaled(0.8, thresholds) - 0.75) < 1e-9)
        #expect(Health.scaled(0.9, thresholds) == 1)
        #expect(Health.scaled(3, thresholds) == 1)
    }

    @Test func countScaling() {
        #expect(Health.counted(0, limit: 5) == 0)
        #expect(Severity(score: Health.counted(1, limit: 5)) == .warning)
        #expect(Severity(score: Health.counted(4, limit: 5)) == .warning)
        #expect(Severity(score: Health.counted(5, limit: 5)) == .critical)
    }

    @Test func cpuAndMemoryAgainstLimitThenRequest() {
        let limited = pod("a", resources: ResourceRequirements(requests: ["cpu": "100m"], limits: ["cpu": "500m", "memory": "100Mi"]))
        let requested = pod("b", resources: ResourceRequirements(requests: ["cpu": "200m"]))
        let unbounded = pod("c")
        let snapshot = ClusterSnapshot.build(
            pods: [limited, requested, unbounded],
            metrics: [
                metrics("a", cpu: "250m", memory: "95Mi"), metrics("b", cpu: "100m", memory: "10Mi"),
                metrics("c", cpu: "1", memory: "1Gi"),
            ],
            events: [], now: now)
        let a = snapshot.pod("shop/a")!
        #expect(a.cpu.basis == .limit)
        #expect(a.cpu.ratio == 0.5)
        #expect(Severity(score: Health.score(a, .cpu, thresholds)!) == .ok)
        #expect(Severity(score: Health.score(a, .memory, thresholds)!) == .critical)
        #expect(Health.label(a, .cpu) == "250m, 50% of limit")

        let b = snapshot.pod("shop/b")!
        #expect(b.cpu.basis == .request)
        #expect(b.cpu.ratio == 0.5)
        #expect(b.memory.basis == .none)

        let c = snapshot.pod("shop/c")!
        #expect(Health.score(c, .cpu, thresholds) == nil)
        #expect(Health.label(c, .cpu) == "1 core, no limit")
    }

    @Test func missingMetrics() {
        let snapshot = ClusterSnapshot.build(pods: [pod("a")], metrics: nil, events: nil, now: now)
        #expect(!snapshot.metricsAvailable)
        #expect(!snapshot.eventsAvailable)
        #expect(Health.score(snapshot.pods[0], .cpu) == nil)
        #expect(Health.label(snapshot.pods[0], .memory) == "no metrics")
    }

    @Test func restartsCountOnlyWhenRecent() {
        func restarted(_ name: String, count: Int, finished: TimeInterval) -> Pod {
            pod(name, statuses: [
                ContainerStatus(
                    name: "app", restartCount: count, state: ContainerState(running: .init()),
                    lastState: ContainerState(terminated: .init(reason: "Error", exitCode: 1, finishedAt: ago(finished))))
            ])
        }
        let snapshot = ClusterSnapshot.build(
            pods: [restarted("fresh", count: 7, finished: 600), restarted("old", count: 40, finished: 86_400), pod("calm")],
            metrics: nil, events: nil, now: now)
        let fresh = snapshot.pod("shop/fresh")!
        #expect(fresh.recentRestarts == 7)
        #expect(fresh.lastRestartReason == "Error")
        #expect(Health.score(fresh, .restarts) == 1)

        let old = snapshot.pod("shop/old")!
        #expect(old.restarts == 40)
        #expect(old.recentRestarts == 0)
        #expect(Health.score(old, .restarts) == 0)
        #expect(Health.label(old, .restarts) == "40 restarts")
        #expect(Health.score(snapshot.pod("shop/calm")!, .restarts) == 0)
    }

    @Test func podStates() {
        func state(_ pod: Pod) -> PodState {
            ClusterSnapshot.podState(pod, cutoff: now.addingTimeInterval(-3600))
        }
        #expect(state(pod("ok")) == PodState("Running", .ok))
        #expect(state(pod("done", phase: "Succeeded")) == PodState("Completed", .ok))
        #expect(state(pod("gone", phase: "Failed")) == PodState("Failed", .critical))
        #expect(state(pod("wait", phase: "Pending", statuses: [])) == PodState("Pending", .warning))
        #expect(
            state(pod("creating", phase: "Pending", statuses: [
                ContainerStatus(name: "app", ready: false, state: ContainerState(waiting: .init(reason: "ContainerCreating")))
            ])) == PodState("ContainerCreating", .warning))
        #expect(
            state(pod("crash", statuses: [
                ContainerStatus(name: "app", ready: false, restartCount: 9, state: ContainerState(waiting: .init(reason: "CrashLoopBackOff")))
            ])) == PodState("CrashLoopBackOff", .critical))
        #expect(
            state(pod("image", phase: "Pending", statuses: [
                ContainerStatus(name: "app", ready: false, state: ContainerState(waiting: .init(reason: "ImagePullBackOff")))
            ])) == PodState("ImagePullBackOff", .critical))
        #expect(
            state(pod("unready", statuses: [ContainerStatus(name: "app", ready: false, state: ContainerState(running: .init()))]))
                == PodState("NotReady", .warning))
        #expect(
            state(pod("oom", statuses: [
                ContainerStatus(
                    name: "app", restartCount: 1, state: ContainerState(running: .init()),
                    lastState: ContainerState(terminated: .init(reason: "OOMKilled", exitCode: 137, finishedAt: ago(120))))
            ])) == PodState("OOMKilled", .critical))
    }

    @Test func crashLoopCountsAsRecentWithoutATimestamp() {
        let crashing = pod("crash", statuses: [
            ContainerStatus(name: "app", ready: false, restartCount: 3, state: ContainerState(waiting: .init(reason: "CrashLoopBackOff")))
        ])
        let snapshot = ClusterSnapshot.build(pods: [crashing], metrics: nil, events: nil, now: now)
        #expect(snapshot.pods[0].recentRestarts == 3)
    }

    @Test func warningEvents() {
        func event(_ name: String, pod: String, count: Int?, last: String?, eventTime: String? = nil) -> Event {
            Event(
                metadata: ObjectMeta(name: name, namespace: "shop"),
                involvedObject: ObjectReference(kind: "Pod", namespace: "shop", name: pod),
                reason: "BackOff", message: "Back-off restarting failed container", count: count,
                lastTimestamp: last, eventTime: eventTime)
        }
        let events = [
            event("e1", pod: "a", count: 6, last: ago(300)),
            event("e2", pod: "a", count: 9, last: ago(7200)),
            event("e3", pod: "a", count: nil, last: nil, eventTime: "2027-01-15T07:59:00.123456Z"),
            Event(metadata: ObjectMeta(name: "e4", namespace: "shop"), involvedObject: ObjectReference(kind: "Node", name: "node-a")),
        ]
        let snapshot = ClusterSnapshot.build(pods: [pod("a"), pod("b")], metrics: nil, events: events, now: now)
        let a = snapshot.pod("shop/a")!
        #expect(a.events.count == 3)
        #expect(a.recentEvents == 7)
        #expect(Severity(score: Health.score(a, .events)!) == .warning)
        #expect(Health.label(a, .events) == "7 warnings")
        #expect(snapshot.pod("shop/b")!.recentEvents == 0)
    }

    @Test func datesWithAndWithoutFractions() {
        #expect(KubeDate.parse("2027-01-15T08:00:00Z") == now)
        #expect(KubeDate.parse("2027-01-15T08:00:00.000000Z") == now)
        #expect(KubeDate.parse(nil) == nil)
    }
}

@Suite struct TreeTests {
    private var snapshot: ClusterSnapshot {
        let crash = pod("api-7d9f8c6b5-bbbbb", statuses: [
            ContainerStatus(name: "app", ready: false, restartCount: 9, state: ContainerState(waiting: .init(reason: "CrashLoopBackOff")))
        ])
        return ClusterSnapshot.build(
            pods: [
                pod("api-7d9f8c6b5-aaaaa", resources: ResourceRequirements(limits: ["cpu": "1"])),
                crash,
                pod("db-0", node: "node-b", owner: OwnerReference(kind: "StatefulSet", name: "db"), labels: nil),
                pod("solo", node: nil, phase: "Pending", owner: nil, labels: nil, statuses: []),
                pod("coredns-abc-1", namespace: "kube-system", owner: OwnerReference(kind: "ReplicaSet", name: "coredns-abc"), labels: ["pod-template-hash": "abc"]),
            ],
            metrics: [
                metrics("api-7d9f8c6b5-aaaaa", cpu: "800m", memory: "64Mi"),
                metrics("db-0", cpu: "100m", memory: "512Mi"),
            ],
            events: [], now: now)
    }

    @Test func groupsByNamespaceThenWorkload() {
        let tree = TreeBuilder.build(snapshot, signal: .status, grouping: .namespace)
        #expect(tree.podCount == 5)
        #expect(tree.children.map(\.name).sorted() == ["kube-system", "shop"])
        let shop = tree.find("ns:shop")!
        #expect(shop.children.map(\.name).sorted() == ["Bare pods", "api", "db"])
        #expect(shop.find("ns:shop/wl:Deployment/api")!.children.count == 2)
        #expect(shop.find("ns:shop/wl:StatefulSet/db")!.kind == .workload("StatefulSet"))
        // Status sizes every pod the same.
        #expect(tree.size == 5)
    }

    @Test func groupsTakeTheWorstChild() {
        let tree = TreeBuilder.build(snapshot, signal: .status, grouping: .namespace)
        #expect(tree.score == 1)
        #expect(tree.criticalCount == 1)
        #expect(tree.warningCount == 1)
        #expect(tree.find("ns:kube-system")!.score == 0)
        #expect(tree.find("ns:shop/wl:Deployment/api")!.score == 1)
    }

    @Test func groupsByNode() {
        let tree = TreeBuilder.build(snapshot, signal: .restarts, grouping: .node)
        #expect(tree.children.map(\.name).sorted() == ["Unscheduled", "node-a", "node-b"])
        #expect(tree.find("node:node-a")!.podCount == 3)
        #expect(tree.find("node:")!.children.first?.podID == "shop/solo")
    }

    @Test func hidesSystemNamespaces() {
        let tree = TreeBuilder.build(snapshot, signal: .status, grouping: .namespace, hideSystem: true)
        #expect(tree.children.map(\.name) == ["shop"])
        #expect(tree.podCount == 4)
    }

    @Test func idlePodsKeepAFloor() {
        let tree = TreeBuilder.build(snapshot, signal: .cpu, grouping: .namespace)
        let leaves = tree.leaves()
        let largest = leaves.map(\.size).max()!
        #expect(largest == 0.8)
        #expect(leaves.allSatisfy { $0.size >= largest * TreeBuilder.sizeFloor })
        // The pod with a limit scores. Pods without one have no data.
        #expect(tree.leaf(forPod: "shop/api-7d9f8c6b5-aaaaa")!.score != nil)
        #expect(tree.leaf(forPod: "shop/db-0")!.score == nil)
    }

    @Test func idsAreStableAcrossSignals() {
        let a = TreeBuilder.build(snapshot, signal: .cpu, grouping: .namespace)
        let b = TreeBuilder.build(snapshot, signal: .events, grouping: .namespace)
        #expect(Set(a.leaves().map(\.id)) == Set(b.leaves().map(\.id)))
        #expect(a.path(to: "ns:shop/wl:StatefulSet/db")!.map(\.name) == ["Cluster", "shop", "db"])
    }

    @Test func emptyClusters() {
        let empty = ClusterSnapshot.build(pods: [], metrics: [], events: [], now: now)
        let tree = TreeBuilder.build(empty, signal: .cpu, grouping: .namespace)
        #expect(tree.children.isEmpty)
        #expect(tree.score == nil)
        #expect(Treemap.layout(tree, in: CGRect(x: 0, y: 0, width: 400, height: 300)).isEmpty)
    }
}

@Suite struct TreemapTests {
    let bounds = CGRect(x: 10, y: 20, width: 800, height: 500)

    @Test func squarifyTilesTheRectangle() {
        let values: [Double] = [6, 6, 4, 3, 2, 2, 1]
        let rects = Treemap.squarify(values, in: bounds)
        let total = values.reduce(0, +)
        for (value, rect) in zip(values, rects) {
            #expect(bounds.insetBy(dx: -0.001, dy: -0.001).contains(rect))
            let expected = Double(bounds.width * bounds.height) * value / total
            #expect(abs(Double(rect.width * rect.height) - expected) < 0.01)
        }
        for i in rects.indices {
            for j in rects.indices where j > i {
                let overlap = rects[i].intersection(rects[j])
                #expect(overlap.isNull || overlap.width * overlap.height < 0.01)
            }
        }
    }

    @Test func squarifyKeepsTilesCloseToSquare() {
        let rects = Treemap.squarify([Double](repeating: 1, count: 12), in: CGRect(x: 0, y: 0, width: 400, height: 300))
        #expect(rects.allSatisfy { max($0.width / $0.height, $0.height / $0.width) < 2 })
    }

    @Test func squarifyHandlesDegenerateInput() {
        #expect(Treemap.squarify([], in: bounds).isEmpty)
        #expect(Treemap.squarify([1, 1], in: .zero) == [.zero, .zero])
        #expect(Treemap.squarify([0, 0], in: bounds) == [.zero, .zero])
        #expect(Treemap.squarify([5], in: bounds) == [bounds])
    }

    private func tree(pods: Int) -> TreeNode {
        let leaves = (0..<pods).map {
            TreeNode(id: "ns:a/wl:Deployment/web/pod:a/p\($0)", name: "p\($0)", kind: .pod, size: 1, score: 0, podID: "a/p\($0)")
        }
        let workload = TreeBuilder.group(id: "ns:a/wl:Deployment/web", name: "web", kind: .workload("Deployment"), children: leaves)
        let namespace = TreeBuilder.group(id: "ns:a", name: "a", kind: .namespace, children: [workload])
        return TreeBuilder.group(id: "cluster", name: "Cluster", kind: .cluster, children: [namespace])
    }

    @Test func layoutNestsGroupsAndStaysInBounds() {
        let tiles = Treemap.layout(tree(pods: 8), in: bounds)
        #expect(tiles.count == 10)
        #expect(tiles[0].style == .group)
        #expect(tiles[0].header != nil)
        #expect(tiles.filter { $0.style == .leaf }.count == 8)
        #expect(tiles.allSatisfy { bounds.contains($0.rect) })
        let workload = tiles[1]
        #expect(tiles.filter { $0.style == .leaf }.allSatisfy { workload.rect.contains($0.rect) })
    }

    @Test func smallGroupsCollapse() {
        let tiles = Treemap.layout(tree(pods: 8), in: CGRect(x: 0, y: 0, width: 50, height: 40))
        #expect(tiles.count == 1)
        #expect(tiles[0].style == .collapsed)
    }

    @Test func hitTestFindsTheDeepestTile() {
        let tiles = Treemap.layout(tree(pods: 8), in: bounds)
        let leaf = tiles.last!
        #expect(Treemap.hitTest(tiles, at: CGPoint(x: leaf.rect.midX, y: leaf.rect.midY))?.id == leaf.id)
        let header = tiles[0].header!
        #expect(Treemap.hitTest(tiles, at: CGPoint(x: header.midX, y: header.minY + 2))?.id == "ns:a")
        #expect(Treemap.hitTest(tiles, at: CGPoint(x: -5, y: -5)) == nil)
    }

    @Test func zoomingLaysOutTheSubtree() {
        let root = tree(pods: 4)
        let tiles = Treemap.layout(root.find("ns:a/wl:Deployment/web")!, in: bounds)
        #expect(tiles.count == 4)
        #expect(tiles.allSatisfy { $0.style == .leaf && $0.depth == 0 })
    }
}

@Suite struct KubeConfigTests {
    let yaml = """
        apiVersion: v1
        kind: Config
        current-context: staging
        clusters:
        - name: local
          cluster:
            server: https://127.0.0.1:6443
            certificate-authority: ca.crt
        - name: gke
          cluster:
            server: https://34.1.2.3
            certificate-authority-data: LS0tLS1CRUdJTi0tLS0t
        contexts:
        - name: dev
          context: {cluster: local, user: dev-user}
        - name: staging
          context: {cluster: gke, user: gke-user}
        users:
        - name: dev-user
          user:
            client-certificate: client.crt
            client-key: client.key
        - name: gke-user
          user:
            exec:
              apiVersion: client.authentication.k8s.io/v1beta1
              command: gke-gcloud-auth-plugin
              args: ["--flag"]
              env:
              - {name: A, value: B}
        """

    @Test func parsesContextsAndUsers() throws {
        let config = try KubeConfig.parse(yaml)
        #expect(config.contextNames == ["dev", "staging"])
        #expect(config.clusters[0].cluster.ca == "ca.crt")
        #expect(config.users[0].user?.clientKey == "client.key")
        #expect(config.users[1].user?.exec?.command == "gke-gcloud-auth-plugin")
        #expect(config.users[1].user?.exec?.env?.first?.value == "B")
    }

    @Test func picksAContext() throws {
        let config = try KubeConfig.parse(yaml)
        #expect(config.contextName(preferring: "dev") == "dev")
        #expect(config.contextName(preferring: "deleted") == "staging")
        #expect(config.contextName(preferring: nil) == "staging")
        #expect(try KubeConfig.parse("kind: Config").contextName(preferring: nil) == nil)
    }

    @Test func reportsMissingAndBrokenFiles() {
        #expect(throws: KubeError.configNotFound("/nonexistent/kubeconfig")) {
            try KubeConfig.load(path: "/nonexistent/kubeconfig")
        }
        #expect(throws: KubeError.self) { try KubeConfig.parse("clusters: 3") }
    }

    @Test func resolvesStaticTokens() async throws {
        let config = try KubeConfig.parse("""
            current-context: c
            clusters:
            - name: k
              cluster: {server: "https://10.0.0.5:6443"}
            contexts:
            - name: c
              context: {cluster: k, user: u}
            users:
            - name: u
              user: {token: abc123}
            """)
        let credentials = try await CredentialResolver.resolve(config, context: "c", configPath: "/tmp/config")
        #expect(credentials.token == "abc123")
        #expect(credentials.server.absoluteString == "https://10.0.0.5:6443")
        // A private address with no CA is treated as a local cluster.
        #expect(credentials.insecure)
        await #expect(throws: KubeError.contextNotFound("nope")) {
            try await CredentialResolver.resolve(config, context: "nope", configPath: "/tmp/config")
        }
    }

    @Test func localAddresses() {
        #expect(CredentialResolver.isLocal(URL(string: "https://127.0.0.1:58725")!))
        #expect(CredentialResolver.isLocal(URL(string: "https://192.168.49.2:8443")!))
        #expect(CredentialResolver.isLocal(URL(string: "https://172.20.0.2")!))
        #expect(!CredentialResolver.isLocal(URL(string: "https://34.1.2.3")!))
        #expect(!CredentialResolver.isLocal(URL(string: "https://172.40.0.2")!))
        #expect(!CredentialResolver.isLocal(URL(string: "https://api.example.com")!))
    }

    @Test func extractsTheFirstCertificateFromPEM() {
        let pem = "-----BEGIN CERTIFICATE-----\nAQID\nBAUG\n-----END CERTIFICATE-----\n-----BEGIN CERTIFICATE-----\nBwgJ\n-----END CERTIFICATE-----\n"
        #expect(CredentialResolver.der(Data(pem.utf8)) == Data([1, 2, 3, 4, 5, 6]))
        #expect(CredentialResolver.der(Data([0x30, 0x82])) == Data([0x30, 0x82]))
    }

    @Test func decodesAPIObjects() throws {
        let json = """
            {"items":[{"metadata":{"name":"web-1","namespace":"shop","ownerReferences":[{"apiVersion":"apps/v1","kind":"StatefulSet","name":"web","uid":"x","controller":true}]},
            "spec":{"nodeName":"n1","containers":[{"name":"c","image":"nginx","resources":{"limits":{"cpu":"500m"}}}]},
            "status":{"phase":"Running","containerStatuses":[{"name":"c","ready":true,"restartCount":2,"state":{"running":{"startedAt":"2027-01-15T07:00:00Z"}},"lastState":{"terminated":{"exitCode":137,"reason":"OOMKilled","finishedAt":"2027-01-15T07:50:00Z"}}}]}}]}
            """
        struct List: Decodable { let items: [Pod] }
        let pods = try JSONDecoder().decode(List.self, from: Data(json.utf8)).items
        let info = ClusterSnapshot.build(pods: pods, metrics: nil, events: nil, now: now).pods[0]
        #expect(info.workload == Workload(kind: "StatefulSet", name: "web"))
        #expect(info.node == "n1")
        #expect(info.cpu.bound == 0.5)
        #expect(info.restarts == 2)
        #expect(info.state == PodState("OOMKilled", .critical))
    }
}

@Suite struct IdentityTests {
    /// A throwaway self-signed certificate and key, as PEM.
    private func selfSigned(_ keyArguments: [String]) async throws -> (certificate: Data, key: Data) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = directory.appendingPathComponent("client.key").path
        let certificate = directory.appendingPathComponent("client.crt").path
        _ = try await Shell.run(
            "/usr/bin/openssl",
            arguments: ["req", "-x509", "-nodes", "-days", "1", "-subj", "/CN=clustermap-test"] + keyArguments
                + ["-keyout", key, "-out", certificate])
        return (FileManager.default.contents(atPath: certificate)!, FileManager.default.contents(atPath: key)!)
    }

    @Test func buildsAnIdentityFromLooseRSAFiles() async throws {
        let pair = try await selfSigned(["-newkey", "rsa:2048"])
        let identity = try await IdentityService.identity(certificatePEM: pair.certificate, keyPEM: pair.key)
        var certificate: SecCertificate?
        #expect(SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess)
        #expect(SecCertificateCopySubjectSummary(certificate!) as String? == "clustermap-test")
        var key: SecKey?
        #expect(SecIdentityCopyPrivateKey(identity, &key) == errSecSuccess)
    }

    @Test func buildsAnIdentityFromLooseECFiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let parameters = directory.appendingPathComponent("ec.pem").path
        _ = try await Shell.run("/usr/bin/openssl", arguments: ["ecparam", "-name", "prime256v1", "-out", parameters])
        let pair = try await selfSigned(["-newkey", "ec:\(parameters)"])
        _ = try await IdentityService.identity(certificatePEM: pair.certificate, keyPEM: pair.key)
    }

    @Test func aCertificateWithoutAKeyIsAnError() async throws {
        let pair = try await selfSigned(["-newkey", "rsa:2048"])
        await #expect(throws: KubeError.self) {
            try await IdentityService.identity(certificatePEM: pair.certificate, keyPEM: nil)
        }
    }

    @Test func missingCommandsAndFailuresAreReported() async {
        await #expect(throws: KubeError.execMissing("clustermap-no-such-plugin")) {
            try await Shell.run("clustermap-no-such-plugin")
        }
        await #expect(throws: KubeError.self) { try await Shell.run("/usr/bin/false") }
        await #expect(throws: KubeError.self) { try await Shell.run("/bin/sleep", arguments: ["5"], timeout: 0.3) }
    }
}

/// Runs against a real cluster when CLUSTERMAP_LIVE_KUBECONFIG points at a kubeconfig. Skipped otherwise.
@Suite struct LiveClusterTests {
    static let kubeconfig = ProcessInfo.processInfo.environment["CLUSTERMAP_LIVE_KUBECONFIG"]

    @Test(.enabled(if: kubeconfig != nil))
    func loadsASnapshot() async throws {
        let source = ClusterSource()
        let path = Self.kubeconfig!
        let contexts = try source.contexts(kubeconfigPath: path, preferring: nil)
        #expect(contexts.selected != nil)

        let snapshot = try await source.snapshot(kubeconfigPath: path, context: nil)
        #expect(!snapshot.pods.isEmpty)
        #expect(snapshot.eventsAvailable)
        // The second call reuses the connection.
        _ = try await source.snapshot(kubeconfigPath: path, context: nil)

        print("context: \(contexts.selected ?? "-"), pods: \(snapshot.pods.count), metrics: \(snapshot.metricsAvailable), events: \(snapshot.eventsAvailable)")
        for pod in snapshot.pods {
            let scores = Signal.allCases.map { signal in
                "\(signal.rawValue)=\(Health.score(pod, signal).map { String(format: "%.2f", $0) } ?? "-")"
            }
            print("  \(pod.id) [\(pod.workload.kind)/\(pod.workload.name)] node=\(pod.node ?? "-") \(pod.state.label) | \(Health.label(pod, .cpu)) | \(Health.label(pod, .memory)) | \(Health.label(pod, .restarts)) | \(Health.label(pod, .events)) | \(scores.joined(separator: " "))")
        }
        for grouping in Grouping.allCases {
            let tree = TreeBuilder.build(snapshot, signal: .status, grouping: grouping)
            print("\(grouping.rawValue): \(tree.children.map { "\($0.name)(\($0.podCount))" }.joined(separator: ", ")) warning=\(tree.warningCount) critical=\(tree.criticalCount)")
        }
    }
}
