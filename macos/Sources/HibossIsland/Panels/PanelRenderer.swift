// Bounded native renderer for interactive panel components and the chart display seam.
// Exports: PanelRenderer.
// Dependencies: SwiftUI, PanelStore, PanelSpec, PanelWebLeafSlot, and semantic system styles.

import SwiftUI

@MainActor
struct PanelRenderer {
    let spec: PanelSpec
    @ObservedObject var store: PanelStore
    @ObservedObject var webModel: PanelWebModel

    func render(_ id: String) -> AnyView {
        guard let element = spec.elements[id] else { return AnyView(EmptyView()) }
        switch element.type {
        case "Stack": return renderStack(element)
        case "Grid": return renderGrid(element)
        case "Section": return renderSection(element)
        case "Text": return renderText(element)
        case "Select": return renderSelect(element)
        case "NumberInput": return renderNumberInput(element)
        case "Toggle": return renderToggle(element)
        case "Button": return renderButton(element)
        case "Metric": return renderMetric(element)
        case "Progress": return renderProgress(element)
        case "Status": return renderStatus(element)
        case "Table", "LineChart", "BarChart": return renderWebLeaf(element)
        default: return AnyView(Text("Unsupported component: \(element.type)").foregroundStyle(.secondary))
        }
    }

    private func renderStack(_ element: PanelElement) -> AnyView {
        let spacing = element.props["gap"]?.number.map { CGFloat($0) } ?? 14
        if element.props["direction"]?.string == "horizontal" {
            return AnyView(HStack(alignment: .center, spacing: spacing) { children(of: element) })
        }
        return AnyView(VStack(alignment: .leading, spacing: spacing) { children(of: element) })
    }

    private func renderGrid(_ element: PanelElement) -> AnyView {
        let columns = max(1, Int(element.props["columns"]?.number ?? 1))
        let gap = element.props["gap"]?.number.map { CGFloat($0) } ?? 12
        return AnyView(LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: columns), alignment: .leading, spacing: gap) { children(of: element) })
    }

    private func renderSection(_ element: PanelElement) -> AnyView {
        let label = element.props["label"]?.string ?? "Section"
        let description = element.props["description"]?.string
        return AnyView(VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.headline)
            if let description { Text(description).font(.callout).foregroundStyle(.secondary) }
            children(of: element)
        })
    }

    private func renderText(_ element: PanelElement) -> AnyView {
        let value = valueText(element.props["text"])
        return AnyView(Text(value).foregroundStyle(toneColor(element.props["tone"]?.string)))
    }

    @ViewBuilder
    private func children(of element: PanelElement) -> some View {
        ForEach(element.children, id: \.self) { render($0) }
    }

    private func renderSelect(_ element: PanelElement) -> AnyView {
        let label = element.props["label"]?.string ?? "Select"
        let options = element.props["options"]?.array?.compactMap { option -> PanelOption? in
            guard let object = option.object, let id = object["id"]?.string, let text = object["label"]?.string else { return nil }
            return PanelOption(id: id, label: text)
        } ?? []
        let path = element.props["value"]?.object?["$bindState"]?.string ?? ""
        return AnyView(Picker(label, selection: Binding(get: { panelValue(at: path, in: store.state)?.string ?? "" }, set: { store.setText($0, at: path) })) {
            ForEach(options) { option in Text(option.label).tag(option.id) }
        }.accessibilityLabel(label))
    }

    private func renderNumberInput(_ element: PanelElement) -> AnyView {
        let label = element.props["label"]?.string ?? "Number"
        let path = element.props["value"]?.object?["$bindState"]?.string ?? ""
        return AnyView(LabeledContent(label) {
            TextField(label, text: Binding(get: { panelValue(at: path, in: store.state)?.displayText ?? "" }, set: { store.setText($0, at: path) }))
                .textFieldStyle(.roundedBorder).frame(width: 120)
        }.accessibilityLabel(label))
    }

    private func renderToggle(_ element: PanelElement) -> AnyView {
        let label = element.props["label"]?.string ?? "Toggle"
        let path = element.props["value"]?.object?["$bindState"]?.string ?? ""
        return AnyView(Toggle(label, isOn: Binding(get: { panelValue(at: path, in: store.state)?.bool ?? false }, set: { store.setBool($0, at: path) })))
    }

    private func renderButton(_ element: PanelElement) -> AnyView {
        let label = element.props["label"]?.string ?? "Submit"
        return AnyView(Button(label) { store.perform(element.on?["press"]) }.buttonStyle(.borderedProminent))
    }

    private func renderMetric(_ element: PanelElement) -> AnyView {
        let label = element.props["label"]?.string ?? "Metric"
        let value = valueText(element.props["value"])
        let unit = element.props["unit"]?.string
        return AnyView(VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.callout).foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value).font(.title2.bold()).foregroundStyle(.primary)
                if let unit { Text(unit).font(.callout).foregroundStyle(.secondary) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading))
    }

    private func renderProgress(_ element: PanelElement) -> AnyView {
        let label = element.props["label"]?.string ?? "Progress"
        let value = Double(valueText(element.props["value"])).flatMap { $0.isFinite ? $0 : nil } ?? 0
        let minimum = element.props["min"]?.number ?? 0
        let maximum = element.props["max"]?.number ?? 1
        return AnyView(ProgressView(value: max(minimum, min(maximum, value)), total: maximum) { Text(label) }.accessibilityValue("\(value)"))
    }

    private func renderStatus(_ element: PanelElement) -> AnyView {
        let label = element.props["label"]?.string ?? "Status"
        let message = element.props["message"]?.string
        let status = element.props["status"]?.string ?? "pending"
        return AnyView(HStack(alignment: .top, spacing: 8) {
            Circle().fill(statusColor(status)).frame(width: 9, height: 9).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.headline)
                if let message { Text(message).foregroundStyle(.secondary) }
            }
        }.accessibilityElement(children: .combine).accessibilityLabel("\(label): \(message ?? status)"))
    }

    private func renderWebLeaf(_ element: PanelElement) -> AnyView {
        var definition = element.props
        definition["type"] = .string(element.type)
        return AnyView(PanelWebLeafSlot(model: webModel, definition: definition))
    }

    private func valueText(_ value: PanelJSONValue?) -> String {
        guard let value else { return "—" }
        if let path = value.object?["$state"]?.string { return panelValue(at: path, in: store.state)?.displayText ?? "—" }
        return value.displayText.isEmpty ? "—" : value.displayText
    }

    private func toneColor(_ tone: String?) -> Color {
        switch tone { case "positive": return .green; case "warning": return .orange; case "danger": return .red; case "muted": return .secondary; default: return .primary }
    }

    private func statusColor(_ status: String) -> Color {
        switch status { case "success": return .green; case "warning": return .orange; case "error": return .red; case "active": return .blue; default: return .secondary }
    }
}

private struct PanelOption: Identifiable {
    let id: String
    let label: String
}
