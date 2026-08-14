// The Inbox screen: the pending decision queue, live over SSE.
// Exports: InboxView bound to an InboxStore.
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
            if store.connectionState == .disconnected {
                ContentUnavailableView(
                    "Disconnected",
                    systemImage: "wifi.slash",
                    description: Text("Connect in Settings to receive decisions.")
                )
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if store.pending.isEmpty, store.history.isEmpty, let error = store.loadError {
            ContentUnavailableView {
                Label("Can't reach the server", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { Task { await store.refresh() } }
            }
        } else {
            inboxList
        }
    }

    private var inboxList: some View {
        List {
            if store.pending.isEmpty, store.settledCards.isEmpty {
                allClear
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(store.pending) { message in
                pendingRow(message)
            }
            ForEach(store.settledCards) { message in
                settledRow(message)
            }
            ForEach(store.settledHistory) { message in
                NavigationLink(value: SessionRoute(message: message)) {
                    HistoryRow(message: message)
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await store.refresh() }
    }

    private func pendingRow(_ message: HistoryMessage) -> some View {
        MessageCard(
            message: message,
            onChoose: { choice in handleReply(choice, to: message.id) },
            onOpen: { AppRouter.shared.open(messageID: message.id.rawValue) }
        )
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button { replyTarget = message } label: {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            trailingSwipes(for: message)
        }
    }

    private func settledRow(_ message: HistoryMessage) -> some View {
        MessageCard(
            message: message,
            settlement: store.settlement(for: message.id),
            onChoose: { _ in },
            onOpen: { AppRouter.shared.open(messageID: message.id.rawValue) }
        )
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                AppRouter.shared.open(messageID: message.id.rawValue)
            } label: {
                let items = MessageMeta.items(for: message, density: .selected)
                let type = items.first { $0.id == "type" }
                Label(type?.label ?? "Details", systemImage: type?.icon ?? "info.circle")
            }
            .tint(.accentColor)
        }
    }

    @ViewBuilder
    private func trailingSwipes(for message: HistoryMessage) -> some View {
        let options = message.options
        if let first = options.first {
            Button { handleReply(first, to: message.id) } label: {
                Label(first, systemImage: MessageMeta.optionIcon(first))
            }
        }
        if options.count >= 2 {
            Button { handleReply(options[1], to: message.id) } label: {
                Label(options[1], systemImage: MessageMeta.optionIcon(options[1]))
            }
        }
        if options.count > 2 {
            Button { replyTarget = message } label: {
                Label("More", systemImage: "ellipsis")
            }
        }
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
