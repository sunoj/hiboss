// Native, accessible sparkline summaries for the dashboard; null samples split lines.
// Exports: PanelDashboardChart and PanelDashboardTable inside HibossKit.
// Dependencies: SwiftUI, Charts, and PanelDashboardSeries.

import Charts
import SwiftUI

struct PanelDashboardChart: View {
    let series: PanelDashboardSeries
    let accent: Color

    private struct Sample: Identifiable {
        let id: Int
        let value: Double
        let segment: Int
    }

    private var samples: [Sample] {
        var segment = 0
        return series.values.enumerated().compactMap { index, value in
            guard let value else { segment += 1; return nil }
            return Sample(id: index, value: value, segment: segment)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(series.label).lineLimit(2)
                Spacer(minLength: 4)
                if let unit = series.unit { Text(unit).fixedSize() }
            }
            .font(.caption).foregroundStyle(.secondary)
            if samples.isEmpty {
                Text("No samples yet").font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            } else {
                plot.frame(height: 44)
            }
        }
    }

    private var plot: some View {
        Chart(samples) { sample in
            if series.isBar {
                BarMark(x: .value("Sample", sample.id + 1), y: .value(series.unit ?? "Value", sample.value), width: .fixed(16))
                    .foregroundStyle(accent).cornerRadius(3)
            } else {
                LineMark(x: .value("Sample", sample.id + 1), y: .value(series.unit ?? "Value", sample.value),
                         series: .value("Segment", sample.segment))
                    .foregroundStyle(accent).lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
        }
        .chartXScale(domain: 0.5...Double(max(1, series.values.count)) + 0.5)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .accessibilityLabel(series.label)
        .accessibilityValue(series.values.map { $0.map { String($0) } ?? "gap" }.joined(separator: ", "))
    }
}

struct PanelDashboardTable: View {
    let definition: [String: PanelValue]

    private var columns: [[String: PanelValue]] {
        Array((definition["columns"]?.array ?? []).compactMap(\.object).prefix(3))
    }

    var body: some View {
        let rows = definition["rows"]?.array ?? []
        VStack(alignment: .leading, spacing: 6) {
            Text(definition["label"]?.string ?? "Table").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
                GridRow {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                        Text(column["label"]?.string ?? column["id"]?.string ?? "")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                ForEach(Array(rows.prefix(2).enumerated()), id: \.offset) { _, row in
                    Divider().gridCellColumns(max(1, columns.count))
                    GridRow {
                        ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                            Text(row.object?[column["id"]?.string ?? ""]?.displayText ?? "—")
                                .font(.caption).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            if rows.count > 2 {
                Text("\(rows.count - 2) more rows in panel").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
