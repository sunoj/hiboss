// The Inbox screen: pending decisions and full history, live over SSE.
// Exports: InboxView bound to an InboxStore, plus the shared EmptyState.
// Dependencies: SwiftUI, HibossKit, MessageCard, HistoryRow.

import HibossKit
import SwiftUI

struct InboxView: View {
    @ObservedObject var store: InboxStore
    @State private var tab: Tab = .pending
    @State private var replyTarget: HistoryMessage?

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
                Task { await store.reply(choice, to: message.id) }
            }
            .presentationDetents([.height(300)])
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
        Group {
            if store.pending.isEmpty {
                ContentUnavailableView(
                    "All clear",
                    systemImage: "checkmark.circle",
                    description: Text("No decisions are waiting on you.")
                )
            } else {
                List {
                    ForEach(store.pending) { message in
                        MessageCard(
                            message: message,
                            onChoose: { choice in Task { await store.reply(choice, to: message.id) } },
                            onMore: { replyTarget = message }
                        )
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
        .refreshable { await store.refresh() }
    }

    @ViewBuilder
    private var allHistoryContent: some View {
        if store.history.isEmpty {
            ContentUnavailableView(
                "No messages yet",
                systemImage: "tray",
                description: Text("Agent messages will appear here.")
            )
        } else {
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
            .refreshable { await store.refresh() }
        }
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
        case .disconnected, .failed: .secondary
        }
    }
}

/// Native empty-state wrapper used across the message surfaces.
struct EmptyState: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        ContentUnavailableView(title, systemImage: icon, description: Text(detail))
    }
}
