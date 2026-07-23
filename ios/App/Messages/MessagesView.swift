// Messages tab: the full message history as a native list.
// Exports: MessagesView bound to the shared InboxStore.
// Dependencies: SwiftUI, HibossKit, HistoryRow, ReplySheet.

import HibossKit
import SwiftUI

struct MessagesView: View {
    @ObservedObject var store: InboxStore
    @State private var replyTarget: HistoryMessage?

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
                        Button { replyTarget = message } label: { HistoryRow(message: message) }
                            .buttonStyle(.plain)
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
        .sheet(item: $replyTarget) { message in
            ReplySheet(message: message) { choice in
                Task { await store.reply(choice, to: message.id) }
            }
            .presentationDetents([.height(300)])
        }
    }
}
