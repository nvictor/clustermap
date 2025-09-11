//
//  ConsoleView.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import SwiftUI

struct ConsoleView: View {
    @State private var selection = Set<UUID>()

    var body: some View {
        VStack {
            ConsoleHeaderView(selection: $selection)
            Divider()
            LogView(selection: $selection)
        }
    }
}
