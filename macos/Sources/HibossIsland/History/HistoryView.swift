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

    private var sessionGroups: [SessionGroup] {
        HistoryMessageLogic.groupBySession(messages)
    }

    var body: some View {
        historyContent
            .background(Color(nsColor: .windowBackgroundColor))
            .searchable(text: $searchText, placement: .toolbar, prompt: L("Search messages"))
            .toolbar { historyToolbar }
            .task {
                if flow.historyState == .idle { await flow.refreshHistory() }
            }
    }

    /// The filter sits in `.principal` — the centre slot Mail and Xcode use for a segmented
    /// control. At `.navigation` it crowded in beside the traffic lights and collided with
    /// the window title. Status and refresh travel together on the trailing side.
    @ToolbarContentBuilder
    private var historyToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker(L("Filter"), selection: $segment) {
                ForEach(HistorySegment.allCases) { item in
                    Text(item.title(unreadCount: unreadCount)).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(minWidth: 240)
            .accessibilityLabel(L("Message filter"))
        }

        ToolbarItemGroup(placement: .primaryAction) {
            connectionStatus

            Button {
                Task { await flow.refreshHistory() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help(L("Refresh messages"))
            .disabled(flow.historyState == .loading)
            .accessibilityLabel(L("Refresh messages"))
        }
    }

    /// Icon-only, with the state in the tooltip: a toolbar item that grows with its label
    /// gets squeezed and clipped as the window narrows, which is what "SSE connected" did.
    private var connectionStatus: some View {
        Image(systemName: connectionSymbol)
            .foregroundStyle(
                flow.connectionState == .connected ? DesignTokens.live : Color.secondary
            )
            .help(flow.connectionState.label)
            .accessibilityLabel(L("Connection: \(flow.connectionState.label)"))
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
            ProgressView(L("Loading messages…"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if flow.historyMessages.isEmpty || messages.isEmpty {
            ContentUnavailableView(
                emptyTitle,
                systemImage: emptySystemImage,
                description: Text(emptyDescription)
            )
        } else {
            groupedMessageList
        }
    }

    private var groupedMessageList: some View {
        List(selection: $selection) {
            ForEach(sessionGroups) { group in
                Section {
                    ForEach(group.messages) { message in
                        HistoryRow(message: message) { choice in
                            Task { await flow.answerHistory(choice, for: message.id) }
                        }
                        .tag(message.id)
                    }
                } header: {
                    SessionGroupHeader(group: group)
                }
            }
        }
        .listStyle(.inset)
    }

    private var emptyTitle: String {
        if case .failed = flow.historyState { return L("History Unavailable") }
        return messages.isEmpty && !flow.historyMessages.isEmpty
            ? L("No Matching Messages")
            : L("No Messages")
    }

    private var emptySystemImage: String {
        if case .failed = flow.historyState { return "exclamationmark.triangle" }
        return "tray"
    }

    private var emptyDescription: String {
        if case let .failed(message) = flow.historyState { return message }
        if messages.isEmpty && !flow.historyMessages.isEmpty {
            return L("Try a different filter or search.")
        }
        return L("Agent messages will appear here.")
    }
}

private struct SessionGroupHeader: View {
    let group: SessionGroup

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .accessibilityLabel(statusAccessibilityLabel)

            Text(group.id == HistoryMessageLogic.directSessionID ? L("Direct") : group.label)
                .font(.headline)
                .foregroundStyle(Color.primary)
                .lineLimit(1)

            if let agentName = group.agentName {
                Text(agentName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("\(group.messages.count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var statusColor: Color {
        switch group.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "working": DesignTokens.live
        case "waiting", "blocked": Color.orange
        default: Color.secondary
        }
    }

    private var statusAccessibilityLabel: String {
        let cleaned = group.status?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cleaned.isEmpty ? L("Session status unknown") : L("Session \(cleaned)")
    }
}
