// Sessions browser retaining native session rows and message history.
// Exports: ActivityView, ActivitySection and ActivitySectionPicker; the shell owns selection for deep links.
// Dependencies: SwiftUI, HibossKit SessionDirectory/SessionGrouping, InboxStore, and SessionRow.

import HibossKit
import SwiftUI

enum ActivitySection: Hashable {
    case sessions
    case messages
}

struct ActivityView: View {
    @ObservedObject var store: InboxStore
    @Binding var section: ActivitySection
    @ObservedObject var connection: ConnectionStore

    @Environment(\.projectSessions) private var inventory

    @State private var search = ""

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
        VStack(spacing: 0) {
            ActivitySectionPicker(section: $section)
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.xs)
            switch section {
            case .sessions: sessions
            case .messages: MessagesView(store: store, search: search)
            }
        }
        .navigationTitle("Sessions")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search sessions and messages")
        .background(Theme.paper)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ConnectionDot(state: store.connectionState) }
        }
    }

    /// An empty bucket shows nothing: a lone "Needs you" header with no rows reads as a fault.
    @ViewBuilder
    private func sessionSection(
        _ title: Text, sessions: [TodaySession]
    ) -> some View {
        let matches = sessions.filter { session in
            search.isEmpty || [session.localizedLabel, session.branch, session.agentName, session.statusText,
                inventory.first { $0.id == session.id }?.nickname]
                .compactMap { $0 }.joined(separator: " ").localizedCaseInsensitiveContains(search)
        }
        if !matches.isEmpty {
            Section {
                ForEach(matches) { session in
                    RouteLink(value: SessionRoute(id: session.id, label: session.localizedLabel)) {
                        SessionRow(session: session)
                    }
                    .accessibilityIdentifier("activity-session-\(session.id)")
                    .accessibilityHint("Opens the session")
                }
            } header: { title.hbSectionHeader().textCase(nil) }
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
                sessionSection(Text("Idle"), sessions: directory.idle)
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

// Shared segment control sits above the content, matching the native navigation title layout.
struct ActivitySectionPicker: View {
    @Binding var section: ActivitySection
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                picker.pickerStyle(.menu)
            } else {
                picker.pickerStyle(.segmented)
            }
        }
        .frame(maxWidth: .infinity, minHeight: ControlMetric.minTap)
        .accessibilityIdentifier("activity-section")
        .listRowInsets(EdgeInsets())
        .listRowBackground(Theme.paper)
        .listRowSeparator(.hidden)
    }

    private var picker: some View {
        Picker("Sessions", selection: $section) {
            Text("Sessions").tag(ActivitySection.sessions)
            Text("Messages").tag(ActivitySection.messages)
        }
        .labelsHidden()
    }

}
