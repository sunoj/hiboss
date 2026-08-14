// The Inbox screen: the pending decision queue, live over SSE.
// Exports: InboxView bound to an InboxStore, plus the shared ConnectionDot.
// Dependencies: SwiftUI, HibossKit, MessageCard, HistoryRow, ReplySheet.

import HibossKit
import SwiftUI
import UIKit

struct InboxView: View {
    @ObservedObject var store: InboxStore
    @State private var replyTarget: HistoryMessage?
    @State private var actionNote: String?

    var body: some View {
        content
            .navigationTitle("Inbox")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        MessagesView(store: store)
                    } label: {
                        Label("All messages", systemImage: "bubble.left.and.bubble.right")
                    }
                }
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
            case .sent:
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            case .alreadyResolved:
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                actionNote = "That decision was already answered elsewhere."
            case .failed:
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                actionNote = "Couldn't send your reply — check your connection."
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !store.didLoad && store.history.isEmpty {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.pending.isEmpty, store.history.isEmpty, let error = store.loadError {
            ContentUnavailableView {
                Label("Can't reach the server", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { Task { await store.refresh() } }
            }
        } else if store.pending.isEmpty {
            emptyQueue
        } else {
            pendingList
        }
    }

    private var pendingList: some View {
        List {
            ForEach(store.pending) { message in
                MessageCard(
                    message: message,
                    onChoose: { choice in handleReply(choice, to: message.id) },
                    onOpen: { AppRouter.shared.open(messageID: message.id.rawValue) }
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button("Reply") { replyTarget = message }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    trailingSwipes(for: message)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .refreshable { await store.refresh() }
    }

    @ViewBuilder
    private func trailingSwipes(for message: HistoryMessage) -> some View {
        let options = message.options
        if let first = options.first {
            Button(first) { handleReply(first, to: message.id) }
        }
        if options.count >= 2 {
            Button(options[1]) { handleReply(options[1], to: message.id) }
        }
        if options.count > 2 {
            Button("More") { replyTarget = message }
        }
    }

    private var emptyQueue: some View {
        List {
            Section {
                allClear
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if !store.recentActivity.isEmpty {
                Section("Recent") {
                    ForEach(store.recentActivity) { message in
                        NavigationLink(value: message.id) { HistoryRow(message: message) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await store.refresh() }
    }

    private var allClear: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)
            Text("All clear")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Text("No decisions are waiting on you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .accessibilityElement(children: .combine)
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
