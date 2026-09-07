// Reminders-inspired overview followed by native, selectable session rows.
// Exports: OverviewSidebar with live category counts and contextual connection feedback.
// Dependencies: SwiftUI, OverviewSnapshot, OptionFlowStore state types.

import HibossKit
import SwiftUI

struct OverviewSidebar: View {
    let snapshot: OverviewSnapshot
    let selection: OverviewDestination
    let historyState: HistoryState
    let connectionState: ConnectionState
    let onSelect: (OverviewDestination) -> Void
    let onSettings: () -> Void
    let onRefresh: () -> Void

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        List(selection: Binding(get: { selection }, set: { onSelect($0) })) {
            Section {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(OverviewCategory.allCases) { category in
                        OverviewTile(category: category, count: snapshot.count(category),
                            isSelected: selection == .category(category), countsAvailable: countsAvailable) {
                            onSelect(.category(category))
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 8, bottom: 16, trailing: 8))
                .selectionDisabled()
            }
            if panelsDemoEnabled {
                Section {
                    Label(L("Panels"), systemImage: "rectangle.3.group")
                        .tag(OverviewDestination.panels)
                }
            }
            if let notice { connectionNotice(notice).selectionDisabled() }
            Section(L("Sessions")) {
                if snapshot.sessions.isEmpty {
                    Text(L("Your sessions will appear here.")).foregroundStyle(.secondary)
                }
                ForEach(snapshot.sessions) { session in
                    sessionRow(session).tag(OverviewDestination.session(session.id))
                }
            }
            Text(L("Counts reflect recent messages."))
                .font(.caption).foregroundStyle(.secondary)
                .selectionDisabled()
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) { settingsFooter }
        .accessibilityIdentifier("overview.sidebar")
    }

    private var countsAvailable: Bool {
        historyState == .loaded || !snapshot.history.isEmpty
    }

    private var panelsDemoEnabled: Bool {
        ProcessInfo.processInfo.environment["HIBOSS_PANELS_DEMO"] == "1"
    }

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
            Label(text, systemImage: "antenna.radiowaves.left.and.right.slash")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if connectionState == .disconnected {
                Button(L("Settings"), action: onSettings)
            } else if case .failed = historyState {
                Button(L("Try again"), action: onRefresh)
            }
        }
        .padding(.vertical, 8)
    }

    private func sessionRow(_ session: SessionGroup) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "list.bullet")
                .font(.body.weight(.semibold))
                .foregroundStyle(DesignTokens.Overview.ink)
                .frame(width: 30, height: 30)
                .background(DesignTokens.Overview.needsYou, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(session.id == SessionGrouping.directSessionID ? L("Direct") : session.label)
                    .font(.body.weight(.medium)).lineLimit(1)
                if let agent = session.agentName {
                    Text(agent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text("\(session.messages.count)").monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var settingsFooter: some View {
        VStack(spacing: 0) {
            Divider()
            Button(action: onSettings) {
                Label(L("Settings"), systemImage: "gear")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).padding(14)
        }
    }
}
