// Session-scoped live panel cards with freshness and the existing questionnaire detail.
// Exports SessionPanelCards; identity comes from panel metadata, never a display label.
// Dependencies: HibossKit PanelsModel, PanelDashboardCard, and HomePanelDetail.

import HibossKit
import SwiftUI

struct SessionPanelCards: View {
    let sessionID: String
    @ObservedObject var model: PanelsModel

    var tiles: [PanelTile] {
        model.tiles.filter {
            $0.metadata?.sessionId == sessionID && !$0.lifecycle.taskState.isTerminal
                && panelIsVisibleInActiveWall(taskState: $0.lifecycle.taskState,
                    placement: $0.preference.placement,
                    expiresAt: $0.lifecycle.expiresAt.flatMap(ISODate.parse),
                    serverTime: model.serverNow(for: $0.id))
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(tiles) { tile in
                PanelDashboardCard(tile: tile, freshness: displayedPanelFreshness(tile, model: model),
                                   pendingCount: model.pendingCount(for: tile)) { model.open(tile.id) }
                    .accessibilityIdentifier("session-panel-\(tile.id)")
                    .contextMenu { PanelLifecycleMenu(tile: tile, model: model) }
            }
        }
        .task { await model.loadIfNeeded() }
        .sheet(isPresented: Binding(get: { model.selectedTile != nil },
                                   set: { if !$0 { model.closeDetail() } })) {
            if let tile = model.selectedTile { HomePanelDetail(tile: tile, model: model) }
        }
    }
}
