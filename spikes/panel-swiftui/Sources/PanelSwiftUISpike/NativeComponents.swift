// Native SwiftUI controls used by the catalog renderer.
// Exports: display, input, table, and chart component views.
// Dependencies: SwiftUI, AppKit semantic colours, and Swift Charts.

import AppKit
import Charts
import SwiftUI

struct MetricComponent: View {
    let label: String
    let value: String
    let unit: String?

    var body: some View {
        LabeledContent(label) {
            Text([value, unit].compactMap { $0 }.joined(separator: " "))
                .font(.title2)
                .foregroundStyle(.primary)
        }
    }
}

struct ProgressComponent: View {
    let label: String
    let value: Double
    let min: Double
    let max: Double

    var body: some View {
        VStack(alignment: .leading) {
            LabeledContent(label) { Text(value.displayValue).foregroundStyle(.secondary) }
            ProgressView(value: value - min, total: max - min)
        }
    }
}

struct StatusComponent: View {
    let label: String
    let status: String
    let message: String?

    var body: some View {
        Label {
            VStack(alignment: .leading) {
                Text(label).font(.headline)
                if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
            }
        } icon: {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
        }
        .accessibilityElement(children: .combine)
                .accessibilityLabel("\(label), \(status)\(message.map { ", \($0)" } ?? "")")
    }

    private var statusIcon: String {
        switch status { case "success": return "checkmark.circle.fill"; case "error": return "xmark.octagon.fill"; case "warning": return "exclamationmark.triangle.fill"; case "active": return "arrow.triangle.2.circlepath"; default: return "clock" }
    }

    private var statusColor: Color {
        switch status { case "success": return Color(nsColor: .systemGreen); case "error": return Color(nsColor: .systemRed); case "warning": return Color(nsColor: .systemOrange); default: return .secondary }
    }
}

struct TableComponent: View {
    let columns: [TableColumnSpec]
    let rows: [TableRow]

    var body: some View {
        Table(rows) {
            TableColumn(columns.map(\.label).joined(separator: " / ")) { row in
                Text(columns.map { row.values[$0.id]?.displayText ?? "" }.joined(separator: " / ")).foregroundStyle(.primary)
            }
        }
        .frame(minHeight: 140)
    }
}

struct TextInputComponent: View {
    let label: String
    @Binding var value: JSONValue
    let placeholder: String?
    let multiline: Bool

    var body: some View {
        Group {
            if multiline {
                TextEditor(text: stringBinding)
                    .frame(minHeight: 72)
            } else {
                TextField(placeholder ?? label, text: stringBinding)
            }
        }
        .labeledContentStyle(.automatic)
        .accessibilityLabel(label)
    }

    private var stringBinding: Binding<String> {
        Binding(get: { value.string ?? value.displayText }, set: { value = .string($0) })
    }
}

struct NumberInputComponent: View {
    let label: String
    @Binding var value: JSONValue
    let min: Double?
    let max: Double?

    var body: some View {
        TextField(label, text: numberBinding)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel(label)
            .help([min.map { "Minimum \($0)" }, max.map { "Maximum \($0)" }].compactMap { $0 }.joined(separator: ", "))
    }

    private var numberBinding: Binding<String> {
        Binding(
            get: { value.string ?? value.displayText },
            set: { raw in value = Double(raw).map { .number($0) } ?? .string(raw) }
        )
    }
}

struct SelectComponent: View {
    let label: String
    @Binding var value: JSONValue
    let options: [PanelOption]

    var body: some View {
        Picker(label, selection: stringBinding) {
            ForEach(options) { option in Text(option.label).tag(option.id) }
        }
        .accessibilityLabel(label)
    }

    private var stringBinding: Binding<String> {
        Binding(get: { value.string ?? "" }, set: { value = .string($0) })
    }
}

struct MultiSelectComponent: View {
    let label: String
    @Binding var value: JSONValue
    let options: [PanelOption]

    var body: some View {
        Section(label) {
            ForEach(options) { option in
                Toggle(option.label, isOn: Binding(
                    get: { selected.contains(option.id) },
                    set: { update(option.id, selected: $0) }
                ))
            }
        }
    }

    private var selected: [String] { value.array?.compactMap(\.string) ?? [] }

    private func update(_ id: String, selected isSelected: Bool) {
        var values = self.selected.filter { $0 != id }
        if isSelected { values.append(id) }
        value = .array(values.map(JSONValue.string))
    }
}

struct ChartPoint: Identifiable {
    let id: Int
    let value: Double
}

struct LineChartComponent: View {
    let label: String
    let values: [JSONValue]
    let unit: String?

    var body: some View {
        VStack(alignment: .leading) {
            if !label.isEmpty { Text(label).font(.headline) }
            Chart {
                ForEach(runs, id: \.first!.id) { run in
                    ForEach(run) { point in LineMark(x: .value("Sample", point.id), y: .value("Value", point.value)) }
                }
            }
            .frame(minHeight: 180)
            .accessibilityLabel(label.isEmpty ? "Line chart" : label)
            DisclosureGroup("Chart values") {
                ForEach(values.indices, id: \.self) { index in
                    Text("\(index): \(values[index].displayText)\(unit.map { " \($0)" } ?? "")").font(.callout)
                }
            }
        }
    }

    private var runs: [[ChartPoint]] {
        var result: [[ChartPoint]] = [[]]
        for (index, value) in values.enumerated() {
            guard let number = value.number else { if !result[result.count - 1].isEmpty { result.append([]) }; continue }
            result[result.count - 1].append(ChartPoint(id: index, value: number))
        }
        return result.filter { !$0.isEmpty }
    }
}

struct BarChartComponent: View {
    let label: String
    let values: [JSONValue]
    let unit: String?

    var body: some View {
        VStack(alignment: .leading) {
            if !label.isEmpty { Text(label).font(.headline) }
            Chart(values.indices, id: \.self) { index in
                if let number = values[index].number { BarMark(x: .value("Sample", index), y: .value("Value", number)) }
            }
            .frame(minHeight: 180)
            .accessibilityLabel(label.isEmpty ? "Bar chart" : label)
            Text(unit.map { "Unit: \($0)" } ?? "").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct PanelOption: Identifiable {
    let id: String
    let label: String
    var description: String?
}

struct TableColumnSpec: Identifiable {
    let id: String
    let label: String
}

struct TableRow: Identifiable {
    let id: Int
    let values: [String: JSONValue]
}

private extension Double {
    var displayValue: String { rounded() == self ? String(Int(self)) : String(self) }
}
