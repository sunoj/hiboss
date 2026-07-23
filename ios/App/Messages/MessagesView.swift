// Messages tab: the full message history as a native list.
// Exports: MessagesView bound to the shared InboxStore.
// Dependencies: SwiftUI, HibossKit, HistoryRow, ReplySheet.

import HibossKit
import SwiftUI

struct MessagesView: View {
    @ObservedObject var store: InboxStore

    var body: some View {
        Group {
            if store.history.isEmpty {
                ContentUnavailableView(
                    "No messages yet",
                    systemImage: "tray",
                    description: Text("Agent messages will appear here.")
                )
            } else {
                List {
                    ForEach(store.history) { message in
                        NavigationLink(value: message.id) { HistoryRow(message: message) }
                    }
                }
                .listStyle(.plain)
                .refreshable { await store.refresh() }
            }
        }
        .navigationTitle("Messages")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ConnectionDot(state: store.connectionState)
            }
        }
    }
}
