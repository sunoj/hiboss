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
    @State private var expandedSessionIDs: Set<String> = []
    @State private var seededSessionIDs: Set<String> = []

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
            .searchable(text: $searchText, placement: .toolbar, prompt: "Search messages")
            .toolbar { historyToolbar }
            .task {
                if flow.historyState == .idle { await flow.refreshHistory() }
            }
            .onChange(of: sessionGroups.map(\.id)) { _, _ in
                seedExpansion(for: sessionGroups)
            }
    }

    /// The filter sits in `.principal` — the centre slot Mail and Xcode use for a segmented
    /// control. At `.navigation` it crowded in beside the traffic lights and collided with
    /// the window title. Status and refresh travel together on the trailing side.
    @ToolbarContentBuilder
    private var historyToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Filter", selection: $segment) {
                ForEach(HistorySegment.allCases) { item in
                    Text(item.title(unreadCount: unreadCount)).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(minWidth: 240)
            .accessibilityLabel("Message filter")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            connectionStatus

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

    /// Icon-only, with the state in the tooltip: a toolbar item that grows with its label
    /// gets squeezed and clipped as the window narrows, which is what "SSE connected" did.
    private var connectionStatus: some View {
        Image(systemName: connectionSymbol)
            .foregroundStyle(
                flow.connectionState == .connected ? DesignTokens.live : Color.secondary
            )
            .help(flow.connectionState.label)
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
            groupedMessageList
        }
    }

    private var groupedMessageList: some View {
        List(selection: $selection) {
            ForEach(sessionGroups) { group in
                Section(isExpanded: expansionBinding(for: group.id)) {
                    ForEach(group.messages) { message in
                        HistoryRow(message: message)
                            .tag(message.id)
                    }
                } header: {
                    SessionGroupHeader(group: group)
                }
            }
        }
        .listStyle(.sidebar)
        .onAppear { seedExpansion(for: sessionGroups) }
    }

    private func expansionBinding(for sessionID: String) -> Binding<Bool> {
        Binding(
            get: { expandedSessionIDs.contains(sessionID) },
            set: { isExpanded in
                if isExpanded {
                    expandedSessionIDs.insert(sessionID)
                } else {
                    expandedSessionIDs.remove(sessionID)
                }
            }
        )
    }

    private func seedExpansion(for groups: [SessionGroup]) {
        let newIDs = Set(groups.map(\.id)).subtracting(seededSessionIDs)
        guard !newIDs.isEmpty else { return }
        for group in groups where newIDs.contains(group.id) && group.isExpandedByDefault {
            expandedSessionIDs.insert(group.id)
        }
        seededSessionIDs.formUnion(newIDs)
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

private struct SessionGroupHeader: View {
    let group: SessionGroup

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .accessibilityLabel(statusAccessibilityLabel)

            Text(group.label)
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
        return cleaned.isEmpty ? "Session status unknown" : "Session \(cleaned)"
    }
}
