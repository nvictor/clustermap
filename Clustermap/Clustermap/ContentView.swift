//
//  ContentView.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: ClusterViewModel
    @State private var showInspector = true

    var body: some View {
        TreemapView(node: viewModel.root, maxLeafValue: viewModel.maxLeafValue)
            .inspector(isPresented: $showInspector) {
                Inspector()
            }
            .task {
                if viewModel.root.name == "Welcome" {
                    await viewModel.loadCluster()
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Button(action: viewModel.reload) {
                        Image(systemName: "arrow.clockwise")
                    }
                    Button(action: { showInspector.toggle() }) {
                        Image(systemName: "sidebar.trailing")
                    }
                }
            }
    }
}
