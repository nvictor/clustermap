//
//  LogService.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import Foundation
import SwiftUI

@MainActor
final class LogService: ObservableObject {
    static let shared = LogService()

    @Published private(set) var logEntries: [LogEntry] = []

    func log(_ message: String, type: LogType, function: String = #function) {
        let formattedMessage = "\(function): \(message)"
        let entry = LogEntry(message: formattedMessage, type: type, timestamp: Date())
        logEntries.append(entry)
    }

    func clearLogs() {
        logEntries.removeAll()
    }
}
