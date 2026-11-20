// Gives the split-view window one native refresh action and compact history status.
// Exports WorkspaceToolbar; read progress never disables the workspace action.
// Dependencies: SwiftUI, HibossKit OptionFlowStore, and CachedReadStatus.

import HibossKit
import SwiftUI

struct WorkspaceToolbar: ViewModifier {
    @ObservedObject var flow: OptionFlowStore
    let destination: OverviewDestination
    /// The connection the window is showing. Preview passes connected so the
    /// toolbar matches the sidebar instead of the idle flow.
    var connection: ConnectionState
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
            ToolbarItem(placement: .primaryAction) { connectionStatus }
                .quietStatusBackground()
            ToolbarItem(placement: .primaryAction) {
                // The title names the row when a narrow window moves this item into the overflow menu.
                Button(action: onRefresh) { Label(refreshHelp, systemImage: "arrow.clockwise") }
                    .help(refreshHelp)
                    .keyboardShortcut("r", modifiers: .command)
                    .layoutProbe("workspace.refresh")
            }
        }
    }

    /// A caption, not a second toolbar button. The mark carries the live tint; a label, not a
    /// bare stack, so the overflow menu of a narrow window has a title for it.
    private var connectionStatus: some View {
        Label {
            Text(connectionTitle)
        } icon: {
            Image(systemName: connectionSymbol)
                .foregroundStyle(connection == .connected ? DesignTokens.live : .secondary)
        }
        .labelStyle(.titleAndIcon)
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .help(connection.detail ?? connection.label)
        .layoutProbe("workspace.live")
    }

    private var connectionTitle: String {
        connection == .connected ? L("Live") : connection.label
    }

    private var connectionSymbol: String {
        switch connection {
        case .connected: "checkmark.circle.fill"
        case .connecting: "antenna.radiowaves.left.and.right"
        case .disconnected, .failed: "antenna.radiowaves.left.and.right.slash"
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
