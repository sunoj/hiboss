// Readable dashboard summaries with metrics, progress, charts, and form context.
// Exports: PanelTilePreview; full interactive rendering stays in PanelRenderer.
// Dependencies: SwiftUI, PanelDashboardContent, PanelDashboardChart, and PanelStore.

import SwiftUI

public struct PanelTilePreview: View, Equatable {
    public let tile: PanelTile
    @ObservedObject private var store: PanelStore

    public init(tile: PanelTile) {
        self.tile = tile
        _store = ObservedObject(wrappedValue: tile.store)
    }

    public nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.tile.store === rhs.tile.store && lhs.tile.fixture.spec == rhs.tile.fixture.spec
            && lhs.tile.fixture.summary == rhs.tile.fixture.summary
    }

    public var body: some View {
        PanelTileContent(content: PanelDashboardContent(fixture: tile.fixture, state: store.state), state: store.state)
    }
}

private struct PanelTileContent: View {
    let content: PanelDashboardContent
    let state: PanelValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var accent: Color { content.progress != nil ? .green : .cyan }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !content.metrics.isEmpty || content.progress != nil {
                HStack(alignment: .center, spacing: 16) {
                    if let progress = content.progress { progressRing(progress) }
                    if content.table != nil { tableMetrics } else { metrics }
                }
            }
            if let series = content.series {
                PanelDashboardChart(series: series, accent: accent)
            } else if let table = content.table {
                PanelDashboardTable(definition: table)
            } else if !content.fields.isEmpty {
                formSummary
            } else if let stage = content.stage {
                Text(verbatim: stage).font(.callout).foregroundStyle(.secondary).lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var tableMetrics: some View {
        PanelMetricLayout(columns: 3, gap: 24) {
            ForEach(Array(content.metrics.enumerated()), id: \.offset) { index, metric in
                PanelMetricView(label: metric.label, value: metric.displayValue(in: state), unit: metric.unit,
                                labelFont: .caption,
                                valueFont: index == 0 ? .largeTitle.bold() : .title2.weight(.semibold),
                                unitFont: .caption, valueColor: index == 0 ? accent : .primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let headline = content.metrics.first {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: headline.label).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: headline.displayValue(in: state))
                            .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                            .monospacedDigit().contentTransition(.numericText())
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: headline.displayValue(in: state))
                        if let unit = headline.unit { Text(verbatim: unit).font(.headline) }
                    }
                    .foregroundStyle(accent).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            if content.metrics.count > 1 {
                PanelMetricLayout(columns: 2, gap: 16) {
                    ForEach(Array(content.metrics.dropFirst().enumerated()), id: \.offset) { _, metric in
                        PanelMetricView(label: metric.label, value: metric.displayValue(in: state),
                                        unit: metric.unit, labelFont: .caption2,
                                        valueFont: .subheadline.weight(.semibold), unitFont: .subheadline)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func progressRing(_ progress: PanelDashboardProgress) -> some View {
        ZStack {
            Circle().stroke(accent.opacity(0.16), lineWidth: 9)
            Circle().trim(from: 0, to: progress.fraction)
                .stroke(accent, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: progress.fraction)
            Text(progress.fraction, format: .percent.precision(.fractionLength(0)))
                .font(.title3.bold()).monospacedDigit()
        }
        .frame(width: 76, height: 76).padding(5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progress.label)
        .accessibilityValue(progress.fraction.formatted(.percent.precision(.fractionLength(0))))
    }

    private var formSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "slider.horizontal.3").font(.title).foregroundStyle(.cyan)
            Text(kitL("\(content.fields.count) fields")).font(.title2.bold())
            ForEach(Array(content.fields.prefix(2).enumerated()), id: \.offset) { _, field in
                Text(verbatim: field).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }
}
