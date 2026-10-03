// Workspace heading with one message-history shortcut and an honest queue summary.
// Exports: DashboardWorkspaceHeader; no independent counters or network state.
// Dependencies: SwiftUI and OverviewSnapshot.

import SwiftUI

struct DashboardWorkspaceHeader: View {
    let snapshot: OverviewSnapshot
    let countsAvailable: Bool
    let isPreview: Bool
    let onHistory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    title
                    Spacer(minLength: 24)
                    historyButton
                }
                VStack(alignment: .leading, spacing: 12) {
                    title
                    historyButton
                }
            }
            Text(L("Decisions first. Follow your agents’ progress below."))
                .font(.callout).foregroundStyle(.secondary)
            if isPreview {
                Label(L("Sample decisions · Local preview"), systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Workspace")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(L("Dashboard")).font(.system(size: 30, weight: .bold, design: .rounded))
        }
    }

    private var historyButton: some View {
        Button(action: onHistory) {
            Label(L("All messages"), systemImage: "clock.arrow.circlepath")
        }
        .controlSize(.large)
        .accessibilityIdentifier("dashboard.history")
        .help(countsAvailable ? L("Recent messages") + " · \(snapshot.history.count)" : L("Loading…"))
    }
}
