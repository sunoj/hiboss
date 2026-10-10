// Sessions browser retaining native session rows and message history.
// Exports: ActivityView and ActivitySection; the shell owns selection for deep links.
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
    @Environment(\.dynamicTypeSize) private var typeSize

    @Environment(\.projectSessions) private var inventory

    @State private var search = ""

    private var matchingMessages: [HistoryMessage] {
        store.history.filter {
            [$0.body, $0.content, $0.agentName, $0.sessionLabel].compactMap { $0 }
                .joined(separator: " ").localizedCaseInsensitiveContains(search)
        }
    }

    private var directory: SessionDirectory { store.todaySnapshot(now: .now).sessionDirectory }
    private var isEmpty: Bool {
        ProcessInfo.processInfo.environment["HIBOSS_DEMO_SESSIONS_EMPTY"] == "1"
            || (directory.needsYou + directory.working + directory.idle).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            sectionPicker
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            switch section {
            case .sessions: sessions
            case .messages: MessagesView(store: store, search: search)
            }
        }
        .navigationTitle("Sessions")
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search sessions and messages")
        .background(Theme.paper)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ConnectionDot(state: store.connectionState) }
        }
    }

    private var sectionPicker: some View {
        Group {
            if typeSize.isAccessibilitySize {
                picker.pickerStyle(.menu)
            } else {
                picker.pickerStyle(.segmented)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .accessibilityIdentifier("activity-section")
    }

    private var picker: some View {
        Picker("Sessions", selection: $section) {
            Text("Sessions").tag(ActivitySection.sessions)
            Text("Messages").tag(ActivitySection.messages)
        }
    }

    private func sessionSection(
        _ title: Text, sessions: [TodaySession]
    ) -> some View {
        let matches = sessions.filter { session in
            search.isEmpty || [session.localizedLabel, session.branch, session.agentName, session.statusText,
                inventory.first { $0.id == session.id }?.nickname]
                .compactMap { $0 }.joined(separator: " ").localizedCaseInsensitiveContains(search)
        }
        return Section {
            ForEach(matches) { session in
                NavigationLink(value: SessionRoute(id: session.id, label: session.localizedLabel)) {
                    SessionRow(session: session)
                }
                .accessibilityIdentifier("activity-session-\(session.id)")
                .accessibilityHint("Opens the session")
            }
        } header: { title }
    }

    private var sessions: some View {
        ListStateView(
            isLoading: !store.didLoad || store.isRefreshing,
            error: store.loadError,
            isEmpty: isEmpty,
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
                            NavigationLink(value: message.id) {
                                HistoryRow(message: message,
                                           answerability: store.answerability(for: message.id))
                            }
                                .accessibilityIdentifier("session-search-message-\(message.id.rawValue)")
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .refreshable { await store.refresh() }
    }
}
