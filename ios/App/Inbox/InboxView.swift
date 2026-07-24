// The Inbox screen: pending decisions and full history, live over SSE.
// Exports: InboxView bound to an InboxStore, plus the shared ConnectionDot.
// Dependencies: SwiftUI, HibossKit, MessageCard, HistoryRow.

import HibossKit
import SwiftUI

struct InboxView: View {
    @ObservedObject var store: InboxStore
    @State private var tab: Tab = .pending
    @State private var replyTarget: HistoryMessage?
    @State private var actionNote: String?

    enum Tab: String, CaseIterable, Identifiable {
        case pending = "Pending"
        case all = "All"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $tab) {
                Text("Pending (\(store.pendingCount))").tag(Tab.pending)
                Text("All").tag(Tab.all)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 6)

            content
        }
        .navigationTitle("Inbox")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ConnectionDot(state: store.connectionState)
            }
        }
        .sheet(item: $replyTarget) { message in
            ReplySheet(message: message) { choice in
                await store.reply(choice, to: message.id)
            }
            .presentationDetents([.medium, .large])
        }
        .alert(
            "Heads up",
            isPresented: Binding(get: { actionNote != nil }, set: { if !$0 { actionNote = nil } }),
            presenting: actionNote
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { note in
            Text(note)
        }
    }

    /// Submit a reply and surface a non-success outcome (already-resolved / failed)
    /// so an optimistically-removed card can't silently imply the boss's choice won.
    private func handleReply(_ choice: String, to id: MessageID) {
        Task {
            switch await store.reply(choice, to: id) {
            case .sent: break
            case .alreadyResolved: actionNote = "That decision was already answered elsewhere."
            case .failed: actionNote = "Couldn't send your reply — check your connection."
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if tab == .pending {
            pendingContent
        } else {
            allHistoryContent
        }
    }

    private var pendingContent: some View {
        ListStateView(
            isLoading: !store.didLoad && store.history.isEmpty,
            error: store.history.isEmpty ? store.loadError : nil,
            isEmpty: store.pending.isEmpty,
            emptyIcon: "checkmark.circle",
            emptyTitle: "All clear",
            emptyDetail: "No decisions are waiting on you.",
            onRetry: { await store.refresh() }
        ) {
            List {
                ForEach(store.pending) { message in
                    MessageCard(
                        message: message,
                        onChoose: { choice in handleReply(choice, to: message.id) },
                        onMore: { replyTarget = message }
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
        }
        .refreshable { await store.refresh() }
    }

    private var allHistoryContent: some View {
        ListStateView(
            isLoading: !store.didLoad && store.history.isEmpty,
            error: store.loadError,
            isEmpty: store.history.isEmpty,
            emptyIcon: "tray",
            emptyTitle: "No messages yet",
            emptyDetail: "Agent messages will appear here.",
            onRetry: { await store.refresh() }
        ) {
            List {
                ForEach(SessionGrouping.groupBySession(store.history)) { group in
                    Section {
                        ForEach(group.messages) { message in
                            NavigationLink(value: message.id) { HistoryRow(message: message) }
                        }
                    } header: {
                        SessionSectionHeader(group: group)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .refreshable { await store.refresh() }
    }
}

/// A small colored dot summarising the live connection state.
struct ConnectionDot: View {
    let state: ConnectionState

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(state.label).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch state {
        case .connected: .green
        case .connecting: .orange
        case .failed: .red
        case .disconnected: .secondary
        }
    }
}
