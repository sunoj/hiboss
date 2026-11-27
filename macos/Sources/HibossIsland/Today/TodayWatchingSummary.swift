// Today's short view of live panels: the first running ones and a link to Watching.
// Exports: TodayWatchingSummary.
// Dependencies: SwiftUI, HibossKit PanelsModel and PanelDashboardCard, WatchingRoute.

import HibossKit
import SwiftUI

struct TodayWatchingSummary: View {
    @ObservedObject var panels: PanelsModel
    let onShowAll: () -> Void

    var body: some View {
        let running = WatchingRoute.running(panels.tiles)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("Watching")).font(.headline)
                Text(verbatim: running.count.formatted())
                    .foregroundStyle(TodayStyle.secondary).monospacedDigit()
                Spacer()
                Button(L("Show all"), action: onShowAll)
                    .buttonStyle(.link)
                    .accessibilityIdentifier("today.watching.showAll")
            }
            PanelWallLayout {
                ForEach(running.prefix(WatchingRoute.todayLimit)) { tile in
                    PanelDashboardCard(tile: tile, freshness: panels.freshness(for: tile),
                        pendingCount: panels.pendingCount(for: tile)) { panels.open(tile.id) }
                        .background(TodayStyle.surface, in: RoundedRectangle(cornerRadius: 24))
                        .layoutValue(key: PanelTileSizeLayoutValueKey.self, value: tile.fixture.spec.tileSize)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("today.watching")
    }
}
