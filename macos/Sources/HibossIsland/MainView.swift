// Provides the HiBoss main window with message history and app settings.
// Exports: MainView and SettingsPaneView for native window scenes.
// Dependencies: SwiftUI, AppSettings, HibossAPI, and OptionFlowStore.

import SwiftUI
import HibossKit

struct MainView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var flow: OptionFlowStore

    var body: some View {
        HistoryView(flow: flow)
        .frame(minWidth: 680, minHeight: 460)
    }
}

private struct HistoryView: View {
    @ObservedObject var flow: OptionFlowStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            historyContent
        }
        .task {
            if flow.historyState == .idle { await flow.refreshHistory() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Messages").font(.title2.bold())
                Text("Recent agent and boss messages").foregroundStyle(.secondary)
            }
            Spacer()
            connectionIndicator
            Button {
                Task { await flow.refreshHistory() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh messages")
            .disabled(flow.historyState == .loading)
        }
        .padding(20)
    }

    private var connectionIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(flow.connectionState == .connected ? Color.green : Color.secondary)
                .frame(width: 7, height: 7)
            Text(flow.connectionState.label).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        if flow.historyMessages.isEmpty, flow.historyState == .loading {
            ProgressView("Loading messages…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if flow.historyMessages.isEmpty {
            ContentUnavailableView(
                "No Messages",
                systemImage: "tray",
                description: Text(historyEmptyDescription)
            )
        } else {
            List(flow.historyMessages) { message in
                HistoryRow(message: message)
            }
            .listStyle(.inset)
        }
    }

    private var historyEmptyDescription: String {
        if case let .failed(message) = flow.historyState { return message }
        return "Agent messages will appear here."
    }
}

private struct HistoryRow: View {
    let message: HistoryMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(sender).font(.headline)
                Spacer()
                Text(message.status.capitalized)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(message.body).textSelection(.enabled).lineLimit(5)
            if !message.options.isEmpty {
                Text(message.options.joined(separator: "  ·  "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack {
                Text(directionLabel)
                if message.priority != "normal" { Text(message.priority.uppercased()) }
                Spacer()
                Text(message.createdAt)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
    }

    private var sender: String {
        message.direction == "boss_to_agent" ? "You" : message.agentName ?? "Agent"
    }

    private var directionLabel: String {
        message.direction == "boss_to_agent" ? "Sent to agent" : "From agent"
    }
}
