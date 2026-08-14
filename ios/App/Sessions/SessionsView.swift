// Sessions tab: a live board of agent sessions derived from message history.
// Exports: SessionsView bound to the shared InboxStore.
// Dependencies: SwiftUI, HibossKit SessionGrouping, SessionCard.

import HibossKit
import SwiftUI

struct SessionsView: View {
    @ObservedObject var store: InboxStore

    private var groups: [SessionGroup] { SessionGrouping.groupBySession(store.history) }

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
                    NavigationLink(value: SessionRoute(id: group.id, label: group.localizedLabel)) {
                        SessionCard(group: group)
                    }
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
}
