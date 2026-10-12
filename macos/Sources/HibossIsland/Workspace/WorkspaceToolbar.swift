// Gives the split-view window one native refresh action and compact history status.
// Exports WorkspaceToolbar; read progress never disables the workspace action.
// Dependencies: SwiftUI, HibossKit OptionFlowStore, and CachedReadStatus.

import HibossKit
import SwiftUI

struct WorkspaceToolbar: ViewModifier {
    @ObservedObject var flow: OptionFlowStore
    let destination: OverviewDestination
    let onRefresh: () -> Void

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .status) {
                if usesHistoryStatus {
                    CachedReadStatus(isRefreshing: flow.isRefreshingHistory,
                        updatedAt: flow.historyLoadedAt, failure: historyFailure, retry: onRefresh)
                }
            }
            .quietStatusBackground()
            ToolbarItemGroup(placement: .primaryAction) {
                Image(systemName: flow.connectionState == .connected
                    ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .foregroundStyle(flow.connectionState == .connected ? DesignTokens.live : .secondary)
                    .help(flow.connectionState.label)
                Button(action: onRefresh) { Image(systemName: "arrow.clockwise") }
                    .help(refreshHelp)
                    .keyboardShortcut("r", modifiers: .command)
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
        case .today: L("Refresh Today")
        case .deviceRequests: L("Refresh device requests")
        default: L("Refresh messages")
        }
    }
}
