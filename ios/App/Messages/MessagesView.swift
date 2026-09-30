// Messages tab: the full message history as a native list.
// Exports: MessagesView bound to the shared InboxStore.
// Dependencies: SwiftUI, HibossKit, MessageThreading, HistoryRow.

import HibossKit
import SwiftUI

struct MessagesView: View {
    @ObservedObject var store: InboxStore

    var body: some View {
        ListStateView(
            isLoading: !store.didLoad && store.history.isEmpty,
            error: store.loadError,
            isEmpty: store.history.isEmpty,
            emptyIcon: "tray",
            emptyTitle: String(localized: "No messages yet"),
            emptyDetail: String(localized: "Agent messages will appear here."),
            onRetry: { await store.refresh() }
        ) {
            List {
                ForEach(MessageThreading.items(from: store.history)) { item in
                    NavigationLink(value: item.id) { row(item) }
                }
            }
            .listStyle(.plain)
        }
        .refreshable { await store.refresh() }
    }

    @ViewBuilder
    private func row(_ item: MessageThreading.Item) -> some View {
        switch item {
        case let .agent(message, reply):
            HistoryRow(message: message, answer: MessageThreading.bossAnswer(
                for: message, answer: reply?.body ?? store.settlement(for: message.id)?.answer
            ))
        case let .boss(message):
            BossHistoryRow(message: message)
        }
    }
}
