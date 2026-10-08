// Display components and preview labels for the shared native panel renderer.
// Exports internal PanelRenderer display helpers; interactive controls stay in PanelRenderer.
// Dependencies: SwiftUI, PanelValue, PanelWebLeafSlot and native semantic colours.

import SwiftUI

extension PanelRenderer {
    func renderMetric(_ element: PanelElement) -> AnyView {
        let label = element.props["label"]?.string ?? kitL("Metric")
        let value = valueText(element.props["value"])
        let unit = element.props["unit"]?.string
        return AnyView(PanelMetricView(label: label, value: value, unit: unit))
    }

    func renderProgress(_ element: PanelElement) -> AnyView {
        let label = element.props["label"]?.string ?? kitL("Progress")
        let value = Double(valueText(element.props["value"], formatted: false))
            .flatMap { $0.isFinite ? $0 : nil } ?? 0
        let minimum = element.props["min"]?.number ?? 0
        let maximum = element.props["max"]?.number ?? 1
        return AnyView(ProgressView(value: max(minimum, min(maximum, value)), total: maximum) {
            Text(verbatim: label)
        }
            .accessibilityValue(value.formatted()))
    }

    func renderStatus(_ element: PanelElement) -> AnyView {
        let label = element.props["label"]?.string ?? kitL("Status")
        let message = element.props["message"]?.string
        let status = element.props["status"]?.string ?? "pending"
        return AnyView(HStack(alignment: .top, spacing: 8) {
            Circle().fill(statusColor(status)).frame(width: 9, height: 9).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: label).font(.headline)
                if let message { Text(verbatim: message).foregroundStyle(.secondary) }
            }
        }.accessibilityElement(children: .combine).accessibilityLabel(kitL("\(label): \(message ?? status)")))
    }

    func renderWebLeaf(_ element: PanelElement) -> AnyView {
        var definition = element.props
        definition["type"] = .string(element.type)
        return AnyView(PanelWebLeafSlot(definition: definition, store: store))
    }

    func renderPreviewControl(_ element: PanelElement) -> AnyView {
        let label = element.props["label"]?.string ?? element.type
        return AnyView(Label(label, systemImage: "rectangle.and.pencil.and.ellipsis")
            .font(.caption).foregroundStyle(.secondary))
    }

    func valueText(_ value: PanelValue?, formatted: Bool = true) -> String {
        guard let value else { return "—" }
        let text: (PanelValue) -> String = { formatted ? $0.formattedText : $0.displayText }
        if let path = value.object?["$state"]?.string {
            return panelValue(at: path, in: store.state).map(text) ?? "—"
        }
        return text(value).isEmpty ? "—" : text(value)
    }

    func toneColor(_ tone: String?) -> Color {
        switch tone {
        case "positive": return .green
        case "warning": return .orange
        case "danger": return .red
        case "muted": return .secondary
        default: return .primary
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "success": return .green
        case "warning": return .orange
        case "error": return .red
        case "active": return .blue
        default: return .secondary
        }
    }
}
