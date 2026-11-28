// Today's short view of live panels: two compact cards and a link to the full wall.
// Exports: TodayWatchingSummary, TodayWatchingTile, TodayWatchingLine and WatchingRoute.
// Dependencies: SwiftUI, HibossKit PanelsModel, PanelDashboardContent, PanelFreshnessLabel.

import HibossKit
import SwiftUI

/// Pushes the full panel wall from Today.
struct WatchingRoute: Hashable {}

enum TodayWatchingLine {
    /// "label value unit · label value unit" from the panel's first two headline metrics.
    static func text(_ content: PanelDashboardContent, state: PanelValue) -> String? {
        let parts = content.metrics.prefix(2).map { metric in
            let value = [metric.displayValue(in: state), metric.unit].compactMap { $0 }.joined(separator: " ")
            return metric.label + " " + value
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct TodayWatchingSummary: View {
    @ObservedObject var model: PanelsModel
    /// Today shows this many cards; the rest are one tap away.
    static let limit = 2

    var body: some View {
        let tiles = model.visibleTiles
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text("Watching").hbSectionHeader()
                Spacer()
                NavigationLink(value: WatchingRoute()) {
                    Text("All \(String(model.tiles.count))").font(.hbSmall)
                        .frame(minHeight: ControlMetric.minTap)
                }
                .accessibilityIdentifier("today-watching-all")
            }
            .padding(.horizontal, Space.m)
            if tiles.isEmpty {
                Text("No panels match the current filter.").font(.hbFootnote).foregroundStyle(Theme.ink2)
                    .padding(.horizontal, Space.m)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: Space.s) { cards(tiles) }
                    VStack(spacing: Space.s) { cards(tiles) }
                }
            }
        }
        .padding(.horizontal, Space.m)
        // A container identifier would otherwise replace the identifiers of the cards and the link.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-watching")
    }

    private func cards(_ tiles: [PanelTile]) -> some View {
        ForEach(tiles.prefix(Self.limit)) { tile in
            TodayWatchingTile(tile: tile, store: tile.store,
                              freshness: { displayedPanelFreshness(tile, model: model) }) { model.open(tile.id) }
        }
    }
}

struct TodayWatchingTile: View {
    let tile: PanelTile
    @ObservedObject var store: PanelStore
    let freshness: () -> PanelFreshness
    let open: () -> Void

    var body: some View {
        let content = PanelDashboardContent(fixture: tile.fixture, state: store.state)
        Button(action: open) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(verbatim: tile.fixture.title).font(.hbSmall.weight(.semibold))
                    .foregroundStyle(Theme.ink).lineLimit(1)
                Text(verbatim: TodayWatchingLine.text(content, state: store.state) ?? tile.sourceLabel)
                    .font(.hbFootnote.monospacedDigit()).foregroundStyle(Theme.ink2).lineLimit(2)
                PanelFreshnessLabel(freshness: freshness()).font(.caption).foregroundStyle(Theme.ink3)
            }
            .padding(Space.s)
            .frame(maxWidth: .infinity, minHeight: ControlMetric.minTap, alignment: .topLeading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-watching-\(tile.id)")
    }
}
