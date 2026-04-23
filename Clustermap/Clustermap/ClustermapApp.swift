//
//  ClustermapApp.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import SwiftUI

@main
struct ClustermapApp: App {
    @StateObject private var viewModel = ClusterViewModel()
    @StateObject private var updater = AppUpdater()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .navigationTitle("Clustermap")
        }
        .commands {
            CheckForUpdatesCommands(updater: updater)
        }
    }
}
