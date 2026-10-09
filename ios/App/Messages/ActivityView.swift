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

    private var groups: [SessionGroup] {
        if ProcessInfo.processInfo.environment["HIBOSS_DEMO_SESSIONS_EMPTY"] == "1" { return [] }
        let messages = Dictionary(
            (store.history + store.requiredInputs).map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let groups = Dictionary(uniqueKeysWithValues:
            SessionGrouping.groupBySession(Array(messages.values)).map { ($0.id, $0) })
        let directory = store.todaySnapshot(now: .now).sessionDirectory
        return (directory.needsYou + directory.working + directory.idle).compactMap { groups[$0.id] }
    }

    var body: some View {
        VStack(spacing: 0) {
            sectionPicker
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            switch section {
            case .sessions: sessions
            case .messages: MessagesView(store: store)
            }
        }
        .navigationTitle("Sessions")
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

    private var sessions: some View {
        ListStateView(
            isLoading: !store.didLoad || store.isRefreshing,
            error: store.loadError,
            isEmpty: groups.isEmpty,
            emptyIcon: "square.stack.3d.up",
            emptyTitle: String(localized: "No sessions yet"),
            emptyDetail: String(localized: "Agent sessions appear here as they report in."),
            loadingTitle: String(localized: "Loading sessions…"),
            hasLoaded: store.didLoad,
            onRetry: { await store.refresh() }
        ) {
            List(groups) { group in
                NavigationLink(value: SessionRoute(id: group.id, label: group.localizedLabel)) {
                    SessionRow(group: group)
                }
                .accessibilityIdentifier("activity-session-\(group.id)")
                .accessibilityHint("Opens the session")
            }
            .listStyle(.plain)
        }
        .refreshable { await store.refresh() }
    }
}
