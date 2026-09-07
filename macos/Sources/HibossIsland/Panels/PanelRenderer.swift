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
        case "Select": return renderSelect(element)
        case "NumberInput": return renderNumberInput(element)
        case "Toggle": return renderToggle(element)
        case "Button": return renderButton(element)
        case "Metric": return renderMetric(element)
        case "Text": return AnyView(Text(element.props["value"]?.string ?? ""))
        case "LineChart": return AnyView(PanelWebLeafSlot(model: webModel, definition: element.props))
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
        let path = element.props["value"]?.object?["$state"]?.string ?? ""
        let value = panelValue(at: path, in: store.state)?.displayText ?? "—"
        return AnyView(LabeledContent(label) { Text(value).font(.title2.bold()).foregroundStyle(.primary) })
    }
}

private struct PanelOption: Identifiable {
    let id: String
    let label: String
}
