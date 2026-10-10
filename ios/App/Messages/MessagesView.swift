// Full message history as a native list in Activity's messages segment.
// Exports: MessagesView bound to the shared InboxStore.
// Dependencies: SwiftUI, HibossKit, MessageThreading, HistoryRow.

import HibossKit
import SwiftUI

struct MessagesView: View {
    @ObservedObject var store: InboxStore

    var search = ""
    var sessionID: String? = nil

    private var messages: [HistoryMessage] {
        store.history.filter {
            (sessionID == nil || SessionGrouping.sessionKey(for: $0) == sessionID)
                && (search.isEmpty || [$0.body, $0.content, $0.agentName, $0.sessionLabel]
                    .compactMap { $0 }.joined(separator: " ").localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        ListStateView(
            isLoading: !store.didLoad || store.isRefreshing,
            error: store.loadError,
            isEmpty: messages.isEmpty,
            emptyIcon: "tray",
            emptyTitle: String(localized: "No messages yet"),
            emptyDetail: String(localized: "Agent messages will appear here."),
            hasLoaded: store.didLoad,
            onRetry: { await store.refresh() }
        ) {
            List {
                ForEach(MessageThreading.items(from: messages)) { item in
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
            let settlement = store.settlement(for: message.id)
            HistoryRow(message: message, answer: MessageThreading.bossAnswer(
                for: message, answer: reply?.body ?? settlement?.answer,
                isAutoDefault: reply?.metadata?.isAutoDefault == true || settlement?.isAutoDefault == true
            ), answerability: store.answerability(for: message.id))
        case let .boss(message):
            BossHistoryRow(message: message)
        }
    }
}
