// Sessions list grouped Needs you / Working / Idle, with History (messages, completed) in the toolbar.
// Exports: ActivityView, HistoryRoute and AllMessagesRoute; the shell owns the path for deep links.
// Dependencies: SwiftUI, HibossKit SessionDirectory/SessionGrouping, InboxStore, and SessionRow.

import HibossKit
import SwiftUI

/// The Sessions history list: all messages and completed decisions.
struct HistoryRoute: Hashable {}
/// Every message, newest first, pushed from History.
struct AllMessagesRoute: Hashable {}

struct ActivityView: View {
    @ObservedObject var store: InboxStore
    @ObservedObject var connection: ConnectionStore

    @Environment(\.projectSessions) private var inventory

    @State private var search = ""
    @State private var showsAllIdle = false
    /// Idle sessions shown before "Show more"; idle is the longest and least urgent group.
    private static let idleLimit = 3

    private var matchingMessages: [HistoryMessage] {
        store.history.filter {
            [$0.body, $0.content, $0.agentName, $0.sessionLabel].compactMap { $0 }
                .joined(separator: " ").localizedCaseInsensitiveContains(search)
        }
    }

    private var directory: SessionDirectory { store.todaySnapshot(now: .now).sessionDirectory }
    private func isEmpty(_ directory: SessionDirectory) -> Bool {
        ProcessInfo.processInfo.environment["HIBOSS_DEMO_SESSIONS_EMPTY"] == "1"
            || (directory.needsYou + directory.working + directory.idle).isEmpty
    }

    var body: some View {
        // A fixed view above the list, as the segment was, keeps the large title on a cold open.
        VStack(spacing: 0) {
            Color.clear.frame(height: Space.xs).accessibilityHidden(true)
            sessions
        }
        .navigationTitle("Sessions")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search sessions and messages")
        .background(Theme.paper)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ConnectionDot(state: store.connectionState) }
            ToolbarItem(placement: .topBarTrailing) {
                RouteLink(value: HistoryRoute()) { Image(systemName: "clock.arrow.circlepath") }
                    .accessibilityLabel("History")
                    .accessibilityIdentifier("sessions-history")
            }
        }
    }

    /// An empty bucket shows nothing: a lone "Needs you" header with no rows reads as a fault.
    @ViewBuilder
    private func sessionSection(
        _ title: Text, sessions: [TodaySession], limit: Int? = nil
    ) -> some View {
        let matches = sessions.filter { session in
            search.isEmpty || [session.localizedLabel, session.branch, session.agentName, session.statusText,
                inventory.first { $0.id == session.id }?.nickname]
                .compactMap { $0 }.joined(separator: " ").localizedCaseInsensitiveContains(search)
        }
        if !matches.isEmpty {
            let shown = limit.map { Array(matches.prefix($0)) } ?? matches
            Section {
                ForEach(shown) { session in
                    RouteLink(value: SessionRoute(id: session.id, label: session.localizedLabel)) {
                        SessionRow(session: session)
                    }
                    .accessibilityIdentifier("activity-session-\(session.id)")
                    .accessibilityHint("Opens the session")
                }
                if shown.count < matches.count {
                    Button("Show \(String(matches.count - shown.count)) more") { showsAllIdle = true }
                        .frame(minHeight: ControlMetric.minTap)
                        .accessibilityIdentifier("sessions-show-more")
                }
            } header: {
                HStack {
                    title.hbSectionHeader().textCase(nil)
                    Spacer()
                    Text(verbatim: String(matches.count)).font(.hbFootnote).foregroundStyle(Theme.ink3)
                }
            }
        }
    }

    private var sessions: some View {
        // Built once per redraw: every access rebuilds the whole Today projection.
        let directory = self.directory
        return ListStateView(
            isLoading: !store.didLoad || store.isRefreshing,
            error: store.loadError,
            isEmpty: isEmpty(directory),
            emptyIcon: "square.stack.3d.up",
            emptyTitle: String(localized: "No sessions yet"),
            emptyDetail: String(localized: "Agent sessions appear here as they report in."),
            loadingTitle: String(localized: "Loading sessions…"),
            hasLoaded: store.didLoad,
            onRetry: { await store.refresh() }
        ) {
            List {
                sessionSection(Text("Needs you"), sessions: directory.needsYou)
                sessionSection(Text("Working"), sessions: directory.working)
                sessionSection(Text("Idle"), sessions: directory.idle,
                               limit: search.isEmpty && !showsAllIdle ? Self.idleLimit : nil)
                if !search.isEmpty {
                    Section("Messages") {
                        ForEach(matchingMessages) { message in
                            RouteLink(value: message.id) {
                                HistoryRow(message: message,
                                           answerability: store.answerability(for: message.id))
                            }
                                .accessibilityIdentifier("session-search-message-\(message.id.rawValue)")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .refreshable { await store.refresh() }
    }
}
