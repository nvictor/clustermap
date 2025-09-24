//
//  ClusterViewModel.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import Foundation
import SwiftUI

@MainActor
final class ClusterViewModel: ObservableObject {
    var metric: SizingMetric = .count { didSet { reload() } }
    @Published var root: TreeNode = TreeNode(name: "Welcome", value: 1, children: [])
    @Published var maxLeafValue: Double = 1.0
    @Published var logEntries: [LogEntry] = []
    @Published var selectedPath: [UUID]?
    @Published var kubeconfigPath: String = ConfigLoader.loadDefaultPath()

    private let service = ClusterService()

    func reload() {
        Task { await loadCluster() }
    }

    func loadCluster() async {
        LogService.shared.clearLogs()
        LogService.shared.log("Loading cluster from \(kubeconfigPath)...", type: .info)

        let result = await service.fetchTree(
            from: kubeconfigPath,
            metric: metric
        )

        switch result {
        case .success(let newRoot):
            self.root = newRoot
            self.maxLeafValue = findMaxLeafValue(in: newRoot)
            self.selectedPath = nil    // Reset zoom when loading new data
        case .failure(let error):
            self.root = TreeNode(name: "Error", value: 1, children: [])
            LogService.shared.log("Error: \(error.localizedDescription)", type: .error)
        }
    }

    private func findMaxLeafValue(in node: TreeNode) -> Double {
        if node.isLeaf {
            return node.value
        }
        return node.children.reduce(0) { max($0, findMaxLeafValue(in: $1)) }
    }
}
