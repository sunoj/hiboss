// A compact Today card for one running panel: its title, freshness and one line of values.
// Exports: TodayWatchingTile and TodayWatchingLine (the pure value line).
// Dependencies: SwiftUI, HibossKit PanelTile, PanelStore, PanelDashboardContent, TodayStyle.

import HibossKit
import SwiftUI

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

struct TodayWatchingTile: View {
    let tile: PanelTile
    @ObservedObject var store: PanelStore
    let freshness: () -> PanelFreshness
    let open: () -> Void

    var body: some View {
        let content = PanelDashboardContent(fixture: tile.fixture, state: store.state)
        Button(action: open) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: tile.fixture.title).font(.callout.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 8)
                    PanelFreshnessLabel(freshness: freshness()).font(.caption)
                }
                Text(verbatim: TodayWatchingLine.text(content, state: store.state) ?? tile.sourceLabel)
                    .font(.caption.monospacedDigit()).foregroundStyle(TodayStyle.secondary).lineLimit(1)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TodayStyle.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today.watching.\(tile.id)")
    }
}
