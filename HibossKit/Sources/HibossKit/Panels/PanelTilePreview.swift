// Readable dashboard summaries with metrics, progress, charts, and form context.
// Exports: PanelTilePreview; full interactive rendering stays in PanelRenderer.
// Dependencies: SwiftUI, PanelDashboardContent, PanelDashboardChart, and PanelStore.

import SwiftUI

public struct PanelTilePreview: View {
    public let tile: PanelTile
    @ObservedObject private var store: PanelStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(tile: PanelTile) {
        self.tile = tile
        _store = ObservedObject(wrappedValue: tile.store)
    }

    private var content: PanelDashboardContent { PanelDashboardContent(fixture: tile.fixture, state: store.state) }
    private var accent: Color { content.progress != nil ? .green : .cyan }

    public var body: some View {
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
                Text(stage).font(.callout).foregroundStyle(.secondary).lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var tableMetrics: some View {
        HStack(alignment: .top, spacing: 24) {
            ForEach(Array(content.metrics.enumerated()), id: \.offset) { index, metric in
                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(metric.displayValue(in: store.state))
                        .font(index == 0 ? .largeTitle.bold() : .title2.weight(.semibold))
                        .foregroundStyle(index == 0 ? accent : .primary).monospacedDigit()
                        .contentTransition(.numericText())
                        if let unit = metric.unit { Text(unit).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let headline = content.metrics.first {
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline.label).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(headline.displayValue(in: store.state))
                            .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                            .monospacedDigit().contentTransition(.numericText())
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: headline.displayValue(in: store.state))
                        if let unit = headline.unit { Text(unit).font(.headline) }
                    }
                    .foregroundStyle(accent).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            if content.metrics.count > 1 {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    ForEach(Array(content.metrics.dropFirst().enumerated()), id: \.offset) { _, metric in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(metric.label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            Text(metric.displayValue(in: store.state) + (metric.unit.map { " \($0)" } ?? ""))
                                .font(.subheadline.weight(.semibold)).monospacedDigit().lineLimit(1)
                        }
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
            Text("\(content.fields.count) fields").font(.title2.bold())
            ForEach(Array(content.fields.prefix(2).enumerated()), id: \.offset) { _, field in
                Text(field).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }
}
