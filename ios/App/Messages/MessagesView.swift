// Messages tab: the full message history as a scrollable list.
// Exports: MessagesView bound to the shared InboxStore.
// Dependencies: SwiftUI, HistoryRow, theme tokens.

import SwiftUI

struct MessagesView: View {
    @ObservedObject var store: InboxStore

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
                        ForEach(store.history) { HistoryRow(message: $0) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paper.ignoresSafeArea())
    }
}

struct SessionsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sessions")
                .font(.hbLargeTitle)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 20)
                .padding(.top, 6)
            Spacer()
            EmptyState(
                icon: "chart.bar",
                title: "Session board coming soon",
                detail: "Live agent status will appear here."
            )
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paper.ignoresSafeArea())
    }
}
