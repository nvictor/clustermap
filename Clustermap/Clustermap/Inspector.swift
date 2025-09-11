//
//  Inspector.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import SwiftUI

struct Inspector: View {
    @EnvironmentObject private var viewModel: ClusterViewModel

    var body: some View {
        Form {
            Section("Connection") {
                TextField("kubeconfig path", text: $viewModel.kubeconfigPath)
                    .textFieldStyle(.roundedBorder)
                Button("Load config", action: viewModel.reload)
            }
            Section("Display") {
                Picker("Sizing Metric", selection: $viewModel.metric) {
                    ForEach(SizingMetric.allCases) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
            }
            ConsoleView()
        }
    }
}
