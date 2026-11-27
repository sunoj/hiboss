// Where live panels are shown: the Watching destination, its Today summary, and its sidebar count.
// Exports: WatchingRoute (pure navigation and selection rules).
// Dependencies: HibossKit PanelTile and the main window's OverviewDestination.

import HibossKit

enum WatchingRoute {
    /// Today shows this many running panels and links to Watching for the rest.
    static let todayLimit = 2

    /// Opening a panel shows it in Watching; a session thread keeps its own panel detail.
    static func destination(openingPanelFrom current: OverviewDestination) -> OverviewDestination? {
        switch current {
        case .watching, .session: nil
        default: .watching
        }
    }

    /// Running, not archived: what Today summarises and the sidebar counts, whatever filter the
    /// Watching wall has selected.
    @MainActor static func running(_ tiles: [PanelTile]) -> [PanelTile] {
        tiles.filter { !$0.lifecycle.taskState.isTerminal && $0.preference.placement != .archived }
    }
}
