// Sessions tab: a live board of agent sessions derived from message history.
// Exports: SessionsView bound to the shared InboxStore.
// Dependencies: SwiftUI, HibossKit SessionGrouping, SessionCard, theme tokens.

import HibossKit
import SwiftUI

struct SessionsView: View {
    @ObservedObject var store: InboxStore
    @State private var selected: SessionGroup?

    private var groups: [SessionGroup] { SessionGrouping.groupBySession(store.history) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paper.ignoresSafeArea())
        .sheet(item: $selected) { group in
            SessionDetailView(group: group, store: store)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Sessions").font(.hbLargeTitle).foregroundStyle(Theme.ink)
            Text(subtitle).font(.hbFootnote).foregroundStyle(Theme.ink3)
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    private var subtitle: String {
        let n = groups.count
        let active = groups.filter { $0.isExpandedByDefault }.count
        let base = n == 0 ? "No active sessions" : "\(n) session\(n == 1 ? "" : "s")"
        return active > 0 ? "\(base) · \(active) active · \(store.connectionState.label)"
            : "\(base) · \(store.connectionState.label)"
    }

    @ViewBuilder
    private var content: some View {
        if groups.isEmpty {
            ScrollView {
                EmptyState(
                    icon: "chart.bar",
                    title: "No sessions yet",
                    detail: "Agent sessions appear here as they report in."
                ).padding(.top, 80)
            }
            .refreshable { await store.refresh() }
            .scrollIndicators(.hidden)
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(groups) { group in
                        Button { selected = group } label: { SessionCard(group: group) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 96)
            }
            .refreshable { await store.refresh() }
            .scrollIndicators(.hidden)
        }
    }
}
