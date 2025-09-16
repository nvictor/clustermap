//
//  LogView.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import SwiftUI

struct LogView: View {
    @ObservedObject private var logService = LogService.shared
    @Binding var selection: Set<UUID>

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ForEach(logService.logEntries) { entry in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LogMessageView(log: entry, isSelected: selection.contains(entry.id))
                            .id(entry.id)
                    }
                    .onTapGesture {
                        if selection.contains(entry.id) {
                            selection.remove(entry.id)
                        } else {
                            selection.insert(entry.id)
                        }
                    }
                }
            }
            .onChange(of: logService.logEntries) { _, newEntries in
                if let lastEntry = newEntries.last {
                    proxy.scrollTo(lastEntry.id, anchor: .bottom)
                }
            }
        }
    }
}

struct ConsoleHeaderView: View {
    @ObservedObject private var logService = LogService.shared
    @Binding var selection: Set<UUID>

    var body: some View {
        HStack {
            Text("Console").font(.headline)

            Spacer()

            Button(action: copyLogs) {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy Selected Logs")
            .disabled(selection.isEmpty)

            Button(action: emailLogs) {
                Image(systemName: "envelope")
            }
            .help("Email Logs to Developer")
            .disabled(selection.isEmpty)

            Button(action: {
                selection.removeAll()
                logService.clearLogs()
            }) {
                Image(systemName: "trash")
            }
            .help("Clear Logs")
        }
    }

    private func copyLogs() {
        let entriesToCopy = logService.logEntries.filter { selection.contains($0.id) }
        let logText = entriesToCopy.map { "[\($0.timestamp)] [\($0.type)] \($0.message)" }.joined(
            separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logText, forType: .string)
    }
    
    private func emailLogs() {
        let entriesToEmail = logService.logEntries.filter { selection.contains($0.id) }
        let logText = entriesToEmail.map { entry in
            let timestamp = DateFormatter.emailFormatter.string(from: entry.timestamp)
            return "[\(timestamp)] [\(entry.type.displayName)] \(entry.message)"
        }.joined(separator: "\n")
        
        let emailBody = """
        Hello,
        
        Please find the Clustermap application logs below:
        
        \(logText)
        
        Best regards,
        Clustermap Application
        """
        
        let subject = "Clustermap Logs - \(Date().formatted())"
        let recipient = "noagbodjivictor@gmail.com"
        
        // Create mailto URL
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: emailBody)
        ]
        
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }
}

struct LogMessageView: View {
    let log: LogEntry
    let isSelected: Bool

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack {
            Text(Self.formatter.string(from: log.timestamp)).foregroundColor(.secondary)
            symbol.foregroundColor(color)
            Text(log.message).foregroundColor(color)
        }
        .font(.system(.body, design: .monospaced))
        .background(isSelected ? Color.accentColor : Color.clear)
    }

    private var symbol: some View {
        switch log.type {
        case .info: return Image(systemName: "info.circle")
        case .success: return Image(systemName: "checkmark.circle")
        case .error: return Image(systemName: "xmark.circle")
        }
    }

    private var color: Color {
        switch log.type {
        case .info: return .primary
        case .success: return .green
        case .error: return .red
        }
    }
}

extension DateFormatter {
    static let emailFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}

extension LogType {
    var displayName: String {
        switch self {
        case .info: return "INFO"
        case .success: return "SUCCESS"
        case .error: return "ERROR"
        }
    }
}
