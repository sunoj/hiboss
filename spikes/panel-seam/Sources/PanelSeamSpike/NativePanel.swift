// Native renderer for interactive catalog nodes around one display-only web leaf.
// Exports: PanelRootView and PanelRenderer.
// Dependencies: SwiftUI, PanelStore, fixture models, and WebLeafSlot.

import AppKit
import SwiftUI

struct PanelRootView: View {
    let spec: PanelSpec
    @ObservedObject var store: PanelStore
    @ObservedObject var webModel: WebLeafModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PanelRenderer(spec: spec, store: store, webModel: webModel).render(spec.root)
                if case .submitted = store.actionResult { Text("Submitted").foregroundStyle(.secondary) }
            }
            .padding()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

@MainActor
struct PanelRenderer {
    let spec: PanelSpec
    let store: PanelStore
    let webModel: WebLeafModel

    func render(_ id: String) -> AnyView {
        guard let element = spec.elements[id] else { return AnyView(EmptyView()) }
        switch element.type {
        case "Stack": return renderStack(element)
        case "Select": return renderSelect(element)
        case "NumberInput": return renderNumberInput(element)
        case "Button": return renderButton(element)
        case "LineChart": return AnyView(WebLeafSlot(model: webModel, definition: element.props))
        default: return AnyView(Text("Unsupported component: \(element.type)").foregroundStyle(.secondary))
        }
    }

    private func renderStack(_ element: PanelElement) -> AnyView {
        return element.props["direction"]?.string == "horizontal"
            ? AnyView(HStack(alignment: .center, spacing: 14) { ForEach(element.children, id: \.self) { render($0) } })
            : AnyView(VStack(alignment: .leading, spacing: 14) { ForEach(element.children, id: \.self) { render($0) } })
    }

    private func renderSelect(_ element: PanelElement) -> AnyView {
        let label = element.props["label"]?.string ?? "Select"
        let options = element.props["options"]?.array?.compactMap { option -> PanelOption? in
            guard let object = option.object, let id = object["id"]?.string, let text = object["label"]?.string else { return nil }
            return PanelOption(id: id, label: text)
        } ?? []
        let binding = store.binding(for: element.props["value"]?.object?["$bindState"]?.string ?? "/form/strategy")
        return AnyView(SelectComponent(label: label, value: binding, options: options).accessibilityIdentifier("native-strategy"))
    }

    private func renderNumberInput(_ element: PanelElement) -> AnyView {
        let label = element.props["label"]?.string ?? "Number"
        let path = element.props["value"]?.object?["$bindState"]?.string ?? "/form/trafficPercent"
        let binding = store.binding(for: path)
        return AnyView(NumberInputComponent(label: label, value: binding).accessibilityIdentifier("native-traffic"))
    }

    private func renderButton(_ element: PanelElement) -> AnyView {
        let label = element.props["label"]?.string ?? "Submit"
        return AnyView(Button(label) { store.perform(element.on?["press"]) }.buttonStyle(.borderedProminent).accessibilityIdentifier("native-submit"))
    }
}

private struct PanelOption: Identifiable {
    let id: String
    let label: String
}

private struct SelectComponent: View {
    let label: String
    @Binding var value: JSONValue
    let options: [PanelOption]

    var body: some View {
        Picker(label, selection: Binding(get: { value.string ?? "" }, set: { value = .string($0) })) {
            ForEach(options) { option in Text(option.label).tag(option.id) }
        }
        .accessibilityLabel(label)
    }
}

private struct NumberInputComponent: View {
    let label: String
    @Binding var value: JSONValue

    var body: some View {
        LabeledContent(label) {
            TextField(label, text: Binding(get: { value.displayText }, set: { value = Double($0).map(JSONValue.number) ?? .string($0) }))
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
        }
        .accessibilityLabel(label)
    }
}
