// Gives the split-view window one Live chip, then native refresh and settings actions.
// Exports WorkspaceToolbar; read progress never disables the workspace action.
// Dependencies: SwiftUI, HibossKit OptionFlowStore, and ToolbarLiveChip.

import HibossKit
import SwiftUI

struct WorkspaceToolbar: ViewModifier {
    @ObservedObject var flow: OptionFlowStore
    let destination: OverviewDestination
    /// The connection the window is showing. Preview passes connected so the
    /// toolbar matches the sidebar instead of the idle flow.
    var connection: ConnectionState
    let onRefresh: () -> Void
    let onSettings: () -> Void

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .primaryAction) {
                ToolbarLiveChip(connection: connection, updatedAt: flow.historyLoadedAt,
                    isRefreshing: flow.isRefreshingHistory,
                    failure: usesHistoryStatus ? historyFailure : nil, retry: onRefresh)
            }
            .quietStatusBackground()
            ToolbarItem(placement: .primaryAction) {
                // The title names the row when a narrow window moves this item into the overflow menu.
                Button(action: onRefresh) { Label(refreshHelp, systemImage: "arrow.clockwise") }
                    .help(refreshHelp)
                    .keyboardShortcut("r", modifiers: .command)
                    .layoutProbe("workspace.refresh")
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: onSettings) { Label(L("Settings"), systemImage: "gearshape") }
                    .help(L("Settings"))
                    .layoutProbe("workspace.settings")
            }
        }
    }

    private var usesHistoryStatus: Bool {
        switch destination {
        case .session, .category: true
        default: false
        }
    }

    private var historyFailure: String? {
        if case let .failed(message) = flow.historyState { return message }
        return nil
    }

    private var refreshHelp: String {
        switch destination {
        case .box: L("Refresh Box")
        case .progress: L("Refresh progress")
        case .watching: L("Refresh panels")
        case .today: L("Refresh Today")
        case .deviceRequests: L("Refresh device requests")
        default: L("Refresh messages")
        }
    }
}
