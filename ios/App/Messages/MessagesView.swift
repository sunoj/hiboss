// Messages tab: the full message history as a native list.
// Exports: MessagesView bound to the shared InboxStore.
// Dependencies: SwiftUI, HibossKit, HistoryRow, ReplySheet.

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
                ForEach(store.history) { message in
                    NavigationLink(value: message.id) { HistoryRow(message: message) }
                }
            }
            .listStyle(.plain)
        }
        .refreshable { await store.refresh() }
        .navigationTitle("Messages")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ConnectionDot(state: store.connectionState)
            }
        }
    }
}
