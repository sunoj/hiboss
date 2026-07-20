// Native History window: searchable toolbar, segmented filter, and List.
// Exports: HistoryView as the main macOS window surface.
// Dependencies: SwiftUI, HibossKit OptionFlowStore, HistoryRow, DesignTokens.

import HibossKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject var flow: OptionFlowStore
    @State private var segment: HistorySegment = .all
    @State private var searchText = ""
    @State private var selection: HistoryMessage.ID?

    private var unreadCount: Int {
        HistoryMessageLogic.unreadCount(in: flow.historyMessages)
    }

    private var messages: [HistoryMessage] {
        HistoryMessageLogic.filtered(
            flow.historyMessages,
            segment: segment,
            searchText: searchText
        )
    }

    var body: some View {
        historyContent
            .background(Color(nsColor: .windowBackgroundColor))
            .searchable(text: $searchText, placement: .toolbar, prompt: "Search messages")
            .toolbar { historyToolbar }
            .task {
                if flow.historyState == .idle { await flow.refreshHistory() }
            }
    }

    @ToolbarContentBuilder
    private var historyToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Picker("Filter", selection: $segment) {
                ForEach(HistorySegment.allCases) { item in
                    Text(item.title(unreadCount: unreadCount)).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)
            .accessibilityLabel("Message filter")
        }

        ToolbarItem(placement: .status) {
            connectionStatus
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await flow.refreshHistory() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh messages")
            .disabled(flow.historyState == .loading)
            .accessibilityLabel("Refresh messages")
        }
    }

    private var connectionStatus: some View {
        Label(flow.connectionState.label, systemImage: connectionSymbol)
            .font(.caption)
            .foregroundStyle(
                flow.connectionState == .connected ? DesignTokens.live : Color.secondary
            )
            .accessibilityLabel("Connection: \(flow.connectionState.label)")
    }

    private var connectionSymbol: String {
        switch flow.connectionState {
        case .connected: "antenna.radiowaves.left.and.right"
        case .connecting: "antenna.radiowaves.left.and.right"
        case .failed: "exclamationmark.triangle"
        case .disconnected: "antenna.radiowaves.left.and.right.slash"
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        if flow.historyMessages.isEmpty, flow.historyState == .loading {
            ProgressView("Loading messages…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if flow.historyMessages.isEmpty || messages.isEmpty {
            ContentUnavailableView(
                emptyTitle,
                systemImage: emptySystemImage,
                description: Text(emptyDescription)
            )
        } else {
            List(messages, selection: $selection) { message in
                HistoryRow(message: message)
                    .tag(message.id)
            }
        }
    }

    private var emptyTitle: String {
        if case .failed = flow.historyState { return "History Unavailable" }
        return messages.isEmpty && !flow.historyMessages.isEmpty
            ? "No Matching Messages"
            : "No Messages"
    }

    private var emptySystemImage: String {
        if case .failed = flow.historyState { return "exclamationmark.triangle" }
        return "tray"
    }

    private var emptyDescription: String {
        if case let .failed(message) = flow.historyState { return message }
        if messages.isEmpty && !flow.historyMessages.isEmpty {
            return "Try a different filter or search."
        }
        return "Agent messages will appear here."
    }
}
