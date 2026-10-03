// Native workspace navigation with decision filters and searchable session history.
// Exports: OverviewSidebar with shared snapshot counts and connection recovery.
// Dependencies: SwiftUI, HibossKit, OverviewSnapshot.

import HibossKit
import SwiftUI

struct OverviewSidebar: View {
    let snapshot: OverviewSnapshot
    let selection: OverviewDestination
    let historyState: HistoryState
    let connectionState: ConnectionState
    var deviceRequestCount = 0
    let onSelect: (OverviewDestination) -> Void
    let onSettings: () -> Void
    let onRefresh: () -> Void
    @State private var sessionSearch = ""

    var body: some View {
        VStack(spacing: 0) {
            brand
            List(selection: Binding(get: { selection }, set: { onSelect($0) })) {
                Section(L("Workspace")) {
                    Label(L("Dashboard"), systemImage: "rectangle.3.group")
                        .tag(OverviewDestination.dashboard)
                        .accessibilityIdentifier("overview.dashboard")
                    Label(L("Device Requests"), systemImage: "desktopcomputer.and.arrow.down")
                        .badge(deviceRequestCount)
                        .tag(OverviewDestination.deviceRequests)
                        .accessibilityIdentifier("overview.deviceRequests")
                    categoryRow(.needsYou)
                    categoryRow(.all)
                    categoryRow(.completed)
                }
                Section(L("Decision filters")) {
                    categoryRow(.automatic)
                    categoryRow(.waiting)
                    categoryRow(.urgent)
                }
                Section(L("Sessions")) { sessions }
                if let notice { connectionNotice(notice).selectionDisabled() }
            }
            .listStyle(.sidebar)
            footer
        }
        .accessibilityIdentifier("overview.sidebar")
    }

    private var brand: some View {
        HStack(spacing: 10) {
            Image(systemName: "capsule.tophalf.filled")
                .font(.title2).foregroundStyle(Color.accentColor)
            Text(verbatim: "HiBoss").font(.title2.weight(.bold))
            Spacer()
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 12)
    }

    private func categoryRow(_ category: OverviewCategory) -> some View {
        HStack(spacing: 8) {
            Label(category.title, systemImage: category.symbol)
            Spacer(minLength: 4)
            Text(verbatim: countsAvailable ? snapshot.count(category).formatted() : "—")
                .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        }
        .tag(OverviewDestination.category(category))
        .accessibilityIdentifier("overview.\(category.rawValue)")
    }

    private var sessions: some View {
        Group {
            TextField(L("Find a session"), text: $sessionSearch)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("overview.sessionSearch")
                .selectionDisabled()
            if filteredSessions.isEmpty {
                Text(sessionSearch.isEmpty ? L("Your sessions will appear here.") : L("No matching sessions"))
                    .font(.callout).foregroundStyle(.secondary).selectionDisabled()
            }
            ForEach(filteredSessions) { session in
                sessionRow(session).tag(OverviewDestination.session(session.id))
            }
        }
    }

    private var filteredSessions: [SessionGroup] {
        let query = sessionSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return snapshot.sessions }
        return snapshot.sessions.filter {
            $0.label.localizedStandardContains(query) || ($0.agentName?.localizedStandardContains(query) ?? false)
        }
    }

    private var countsAvailable: Bool { historyState == .loaded || !snapshot.history.isEmpty }

    private var notice: String? {
        if case let .failed(error) = historyState { return error }
        switch connectionState {
        case .disconnected: return L("Connect to receive agent messages.")
        case .failed: return L("Connection interrupted. Showing recent messages.")
        case .connecting: return L("Connecting…")
        case .connected: return nil
        }
    }

    private func connectionNotice(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if connectionState == .disconnected {
                Button(L("Settings"), action: onSettings)
            } else {
                Button(L("Try again"), action: onRefresh)
            }
        }.padding(.vertical, 8)
    }

    private func sessionRow(_ session: SessionGroup) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.id == SessionGrouping.directSessionID ? L("Direct") : session.label)
                    .lineLimit(1)
                if let agent = session.agentName {
                    Text(agent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text(verbatim: session.messages.count.formatted()).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .help(session.label)
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Label(connectionState.label, systemImage: connectionState == .connected
                ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right.slash")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(action: onSettings) { Label(L("Settings"), systemImage: "gearshape") }
                    .buttonStyle(.plain)
                Spacer()
                Text(L("Recent messages")).font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(16)
    }
}
