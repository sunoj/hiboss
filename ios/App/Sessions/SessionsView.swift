// Sessions tab: a live board of agent sessions derived from message history.
// Exports: SessionsView bound to the shared InboxStore.
// Dependencies: SwiftUI, HibossKit SessionGrouping, SessionCard.

import HibossKit
import SwiftUI

struct SessionsView: View {
    @ObservedObject var store: InboxStore

    private var groups: [SessionGroup] {
        // Screenshot-only: demo history is never empty, so the empty board is gated.
        if ProcessInfo.processInfo.environment["HIBOSS_DEMO_SESSIONS_EMPTY"] == "1" {
            return []
        }
        return SessionGrouping.groupBySession(store.history)
    }

    var body: some View {
        ListStateView(
            isLoading: !store.didLoad && store.history.isEmpty,
            error: store.loadError,
            isEmpty: groups.isEmpty,
            emptyIcon: "square.stack.3d.up",
            emptyTitle: String(localized: "No sessions yet"),
            emptyDetail: String(localized: "Agent sessions appear here as they report in."),
            onRetry: { await store.refresh() }
        ) {
            List {
                ForEach(groups) { group in
                    sessionRow(group)
                }
            }
            .listStyle(.plain)
        }
        .refreshable { await store.refresh() }
        .navigationTitle("Sessions")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ConnectionDot(state: store.connectionState)
            }
        }
    }

    /// Same list-row treatment as Inbox pending `MessageCard` rows: the card
    /// draws its own material tile; the list supplies no separator or fill.
    private func sessionRow(_ group: SessionGroup) -> some View {
        NavigationLink(value: SessionRoute(id: group.id, label: group.localizedLabel)) {
            SessionCard(group: group)
        }
        .buttonStyle(.plain)
        .navigationLinkIndicatorVisibility(.hidden)
        .accessibilityHint("Opens the session")
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}
