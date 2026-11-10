import ClustermapCore
import SwiftUI

struct InspectorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let pod = model.selectedPod {
                PodDetail(pod: pod)
            } else if model.snapshot != nil {
                ScopeSummary(scope: model.zoomNode)
            } else {
                ContentUnavailableView("No cluster", systemImage: "square.dashed")
            }
        }
        .formStyle(.grouped)
    }
}

/// Shown when nothing is selected: the group in view, the legend, and the pods that need attention.
private struct ScopeSummary: View {
    @Environment(AppModel.self) private var model
    let scope: TreeNode

    var body: some View {
        let worst = scope.leaves()
            .filter { ($0.score ?? 0) >= 0.5 }
            .sorted { ($0.score ?? 0, $1.name) > ($1.score ?? 0, $0.name) }
            .prefix(5)

        Form {
            Section {
                LabeledContent("Pods", value: "\(scope.podCount)")
                LabeledContent("Warning", value: "\(scope.warningCount)")
                LabeledContent("Critical", value: "\(scope.criticalCount)")
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(scope.name).font(.headline).foregroundStyle(.primary).lineLimit(2)
                    Text(scope.kind.title).font(.caption)
                }
                .textCase(nil)
            }

            Section(model.signal.title) {
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4).fill(model.palette.gradient).frame(height: 12)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.primary.opacity(0.15)))
                    HStack {
                        Text("Healthy")
                        Spacer()
                        Text("Warning")
                        Spacer()
                        Text("Critical")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    if model.signal.needsMetrics {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 3).fill(model.palette.fill(nil)).frame(width: 18, height: 12)
                            Text("No limit or request to compare against").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                Text(model.signal.explanation).font(.caption).foregroundStyle(.secondary)
            }

            Section("Needs Attention") {
                if worst.isEmpty {
                    Label("Nothing to report", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                }
                ForEach(worst) { leaf in
                    Button {
                        model.select(pod: leaf.podID)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(model.palette.fill(leaf.score)).frame(width: 9, height: 9)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(leaf.name).lineLimit(1).truncationMode(.middle)
                                Text(leaf.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Every signal for one pod, so switching tabs is not needed to judge it.
private struct PodDetail: View {
    @Environment(AppModel.self) private var model
    let pod: PodInfo

    var body: some View {
        let now = model.snapshot?.fetchedAt ?? Date()
        Form {
            Section {
                ForEach(Signal.allCases) { signal in
                    Button {
                        model.signal = signal
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: signal.symbol).frame(width: 18).foregroundStyle(.secondary)
                            Text(signal.title)
                            Spacer(minLength: 8)
                            Text(Health.label(pod, signal)).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                            Circle().fill(model.palette.fill(Health.score(pod, signal, model.thresholds))).frame(width: 9, height: 9)
                        }
                        .fontWeight(signal == model.signal ? .semibold : .regular)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Show \(signal.title) on the map")
                }
            } header: {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pod.name).font(.headline).foregroundStyle(.primary).textSelection(.enabled)
                        Text("Pod · \(pod.state.label)").font(.caption)
                    }
                    Spacer()
                    Button {
                        model.selectedPodID = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Close (Escape)").accessibilityLabel("Close pod details")
                }
                .textCase(nil)
            }

            Section("Details") {
                LabeledContent("Namespace", value: pod.namespace)
                LabeledContent(pod.workload.isStandalone ? "Workload" : pod.workload.kind, value: pod.workload.name)
                LabeledContent("Node", value: pod.node ?? "Unscheduled")
                if let created = pod.created {
                    LabeledContent("Age", value: Format.age(now.timeIntervalSince(created)))
                }
                if let last = pod.lastRestart {
                    LabeledContent(
                        "Last Restart",
                        value: "\(Format.age(now.timeIntervalSince(last))) ago" + (pod.lastRestartReason.map { ", \($0)" } ?? ""))
                }
            }

            if !pod.containers.isEmpty {
                Section("Containers") {
                    ForEach(pod.containers) { container in
                        LabeledContent {
                            Text(container.restarts > 0 ? "\(container.state), \(Format.count(container.restarts, "restart"))" : container.state)
                        } label: {
                            Label(container.name, systemImage: container.ready ? "checkmark.circle" : "circle.dotted")
                        }
                    }
                }
            }

            if !pod.events.isEmpty {
                Section("Warning Events") {
                    ForEach(pod.events.prefix(8)) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(event.count > 1 ? "\(event.reason) ×\(event.count)" : event.reason).fontWeight(.medium)
                                Spacer()
                                if let last = event.last {
                                    Text("\(Format.age(now.timeIntervalSince(last))) ago").foregroundStyle(.secondary)
                                }
                            }
                            Text(event.message).font(.caption).foregroundStyle(.secondary).lineLimit(4).textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }
}
