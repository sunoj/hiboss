// Sessions tab: a live board of agent sessions derived from message history.
// Exports: SessionsView bound to the shared InboxStore.
// Dependencies: SwiftUI, HibossKit SessionGrouping, SessionCard.

import HibossKit
import SwiftUI

struct SessionsView: View {
    @ObservedObject var store: InboxStore
    @State private var selected: SessionGroup?

    private var groups: [SessionGroup] { SessionGrouping.groupBySession(store.history) }

    var body: some View {
        ListStateView(
            isLoading: !store.didLoad && store.history.isEmpty,
            error: store.loadError,
            isEmpty: groups.isEmpty,
            emptyIcon: "square.stack.3d.up",
            emptyTitle: "No sessions yet",
            emptyDetail: "Agent sessions appear here as they report in.",
            onRetry: { await store.refresh() }
        ) {
            List {
                ForEach(groups) { group in
                    Button { selected = group } label: { SessionCard(group: group) }
                        .buttonStyle(.plain)
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
        .sheet(item: $selected) { group in
            SessionDetailView(group: group, store: store)
        }
    }
}
