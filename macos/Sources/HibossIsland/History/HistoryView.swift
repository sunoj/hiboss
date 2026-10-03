// Readable session stream with inline messages, search, and shared reply drafts.
// Exports: HistoryView with per-message expansion and no detail sheet.
// Dependencies: SwiftUI, HibossKit, HistoryRow, and OverviewSnapshot.

import HibossKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject var flow: OptionFlowStore
    let snapshot: OverviewSnapshot
    let scope: OverviewDestination
    @ObservedObject var reply: AttentionReplyState

    private var scopedMessages: [HistoryMessage] { snapshot.messages(for: scope) }
    @State private var segment: HistorySegment = .all
    @State private var searchText = ""
    @State private var expandedMessages: Set<MessageID> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var unreadCount: Int {
        HistoryMessageLogic.unreadCount(in: scopedMessages)
    }

    private var messages: [HistoryMessage] {
        HistoryMessageLogic.filtered(
            scopedMessages,
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
            .navigationTitle(snapshot.title(for: scope))
            .onChange(of: scope) { segment = .all; searchText = "" }
            .searchable(text: $searchText, placement: .toolbar, prompt: L("Search messages"))
            .toolbar { historyToolbar }
            .task {
                if flow.historyState == .idle { await flow.refreshHistory() }
            }
    }

    /// The filter sits in `.principal` — the centre slot Mail and Xcode use for a segmented
    /// control. Connection and refresh live on MainView so both surfaces share one chrome.
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
    }

    @ViewBuilder
    private var historyContent: some View {
        if scopedMessages.isEmpty, flow.historyState == .loading {
            ProgressView(L("Loading messages…"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if messages.isEmpty {
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
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(sessionGroups) { group in
                        Section {
                            ForEach(group.messages) { message in
                                messageRow(message, reader: reader)
                                Divider()
                            }
                        } header: {
                            sessionHeader(group)
                        }
                    }
                }
                .frame(maxWidth: 900, alignment: .leading)
                .padding(.horizontal, 24).padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            .id(scope)
            .accessibilityIdentifier("history.stream")
        }
    }

    @ViewBuilder
    private func sessionHeader(_ group: SessionGroup) -> some View {
        if case .session = scope {
            EmptyView()
        } else {
            SessionGroupHeader(group: group, session: flow.projectSessions.first { $0.id == group.id })
                .padding(.vertical, 12)
                .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private func messageRow(_ message: HistoryMessage, reader: ScrollViewProxy) -> some View {
        HistoryRow(message: message, reply: reply, isExpanded: Binding(
            get: { expandedMessages.contains(message.id) },
            set: { expanded in
                if expanded { expandedMessages.insert(message.id) }
                else { expandedMessages.remove(message.id) }
            }), isSearching: !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            onCollapse: {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                    reader.scrollTo(message.id, anchor: .top)
                }
            }, onChoose: { choice in await flow.answer(choice, for: message.id) })
            .id(message.id)
    }

    private var emptyTitle: String {
        if case .failed = flow.historyState { return L("History Unavailable") }
        if scopedMessages.isEmpty, scope == .category(.completed) { return L("No completed questions") }
        return scopedMessages.isEmpty ? L("No Messages") : L("No Matching Messages")
    }

    private var emptySystemImage: String {
        if case .failed = flow.historyState { return "exclamationmark.triangle" }
        return "tray"
    }

    private var emptyDescription: String {
        if case let .failed(message) = flow.historyState { return message }
        if scopedMessages.isEmpty, scope == .category(.completed) {
            return L("Answered and expired questions appear here.")
        }
        if messages.isEmpty && !scopedMessages.isEmpty {
            return L("Try a different filter or search.")
        }
        return L("Agent messages will appear here.")
    }
}

private struct SessionGroupHeader: View {
    let group: SessionGroup
    let session: ProjectSession?

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .accessibilityLabel(statusAccessibilityLabel)

            Text(HistoryMessageLogic.sessionTitle(group: group, session: session))
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

            Text(group.messages.count.formatted())
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
