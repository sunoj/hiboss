// Messages tab: the full message history as a scrollable list.
// Exports: MessagesView bound to the shared InboxStore.
// Dependencies: SwiftUI, HibossKit, HistoryRow, ReplySheet, theme tokens.

import HibossKit
import SwiftUI

struct MessagesView: View {
    @ObservedObject var store: InboxStore
    @State private var replyTarget: HistoryMessage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Messages")
                .font(.hbLargeTitle)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 20)
                .padding(.top, 6)
            Text("\(store.history.count) total · \(store.connectionState.label)")
                .font(.hbFootnote)
                .foregroundStyle(Theme.ink3)
                .padding(.horizontal, 20)
                .padding(.top, 2)

            ScrollView {
                LazyVStack(spacing: 10) {
                    if store.history.isEmpty {
                        EmptyState(
                            icon: "tray",
                            title: "No messages yet",
                            detail: "Agent messages will appear here."
                        ).padding(.top, 80)
                    } else {
                        ForEach(store.history) { message in
                            Button { replyTarget = message } label: { HistoryRow(message: message) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 96)
            }
            .refreshable { await store.refresh() }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paper.ignoresSafeArea())
        .sheet(item: $replyTarget) { message in
            ReplySheet(message: message) { choice in
                Task { await store.reply(choice, to: message.id) }
            }
            .presentationDetents([.height(300)])
        }
    }
}
