// Today's short view of live panels: the first running ones and a link to Watching.
// Exports: TodayWatchingSummary.
// Dependencies: SwiftUI, HibossKit PanelsModel, TodayWatchingTile, WatchingRoute.

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
            HStack(alignment: .top, spacing: 12) {
                ForEach(running.prefix(WatchingRoute.todayLimit)) { tile in
                    TodayWatchingTile(tile: tile, store: tile.store,
                        freshness: { panels.freshness(for: tile) }) { panels.open(tile.id) }
                }
            }
        }
        .accessibilityIdentifier("today.watching")
    }
}
