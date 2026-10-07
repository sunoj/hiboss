// One history browser with native session and message selections.
// Exports: ActivityView and ActivitySection; the shell owns selection for deep links.
// Dependencies: SwiftUI, HibossKit SessionGrouping, InboxStore, MessagesView and SessionRow.

import HibossKit
import SwiftUI

enum ActivitySection: Hashable {
    case sessions
    case messages
}

struct ActivityView: View {
    @ObservedObject var store: InboxStore
    @Binding var section: ActivitySection
    @Environment(\.dynamicTypeSize) private var typeSize

    private var groups: [SessionGroup] {
        if ProcessInfo.processInfo.environment["HIBOSS_DEMO_SESSIONS_EMPTY"] == "1" { return [] }
        return SessionGrouping.groupBySession(store.history)
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
        .navigationTitle("Activity")
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
        Picker("Activity", selection: $section) {
            Text("Sessions").tag(ActivitySection.sessions)
            Text("Messages").tag(ActivitySection.messages)
        }
    }

    private var sessions: some View {
        ListStateView(
            isLoading: !store.didLoad && store.history.isEmpty,
            error: store.loadError,
            isEmpty: groups.isEmpty,
            emptyIcon: "square.stack.3d.up",
            emptyTitle: String(localized: "No sessions yet"),
            emptyDetail: String(localized: "Agent sessions appear here as they report in."),
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
