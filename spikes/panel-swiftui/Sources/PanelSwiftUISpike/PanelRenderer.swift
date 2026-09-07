// General catalog traversal from immutable spec nodes to native SwiftUI views.
// Exports: PanelRenderer and PanelRootView.
// Dependencies: PanelStore, JSON expressions, and NativeComponents.swift.

import SwiftUI

struct PanelRootView: View {
    let spec: PanelSpec
    @ObservedObject var store: PanelStore
    var onInteractive: (() -> Void)?
    var onRevisionApplied: (() -> Void)?

    var body: some View {
        ScrollView {
            PanelRenderer(spec: spec, store: store, onAction: store.perform).render(spec.root)
                .padding()
            ActionStatusView(result: store.actionResult)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { onInteractive?() }
        // The host starts timing before write(); this transaction observer is the view-apply boundary.
        .onChange(of: store.revision, initial: false) { _, _ in onRevisionApplied?() }
    }
}

@MainActor
struct PanelRenderer {
    let spec: PanelSpec
    let store: PanelStore
    let onAction: (PanelAction) -> Void

    func render(_ id: String, context: ExpressionContext = .init(state: .null, item: nil, index: nil)) -> AnyView {
        guard let element = spec.elements[id], isVisible(element.visible, context: context) else { return AnyView(EmptyView()) }
        if let repeatSpec = element.repeatSpec { return renderRepeat(id: id, element: element, repeatSpec: repeatSpec, context: context) }
        guard let kind = ComponentKind(rawValue: element.type) else {
            return AnyView(Text("Unsupported component: \(element.type)").foregroundStyle(.secondary))
        }
        let props = element.props
        switch kind {
        case .stack: return renderStack(element, context: context, vertical: props["direction"]?.string != "horizontal")
        case .grid: return renderGrid(element, context: context, columns: Int(props["columns"]?.number ?? 1))
        case .section: return renderSection(element, context: context)
        case .text: return AnyView(Text(store.resolve(props["text"] ?? .string(""), context: context)?.displayText ?? "").foregroundStyle(textColor(props["tone"]?.string)))
        case .metric: return AnyView(MetricComponent(label: string(props, "label"), value: resolvedText(props["value"], context), unit: props["unit"]?.string))
        case .progress: return AnyView(ProgressComponent(label: string(props, "label"), value: resolvedNumber(props["value"], context), min: props["min"]?.number ?? 0, max: props["max"]?.number ?? 1))
        case .status: return AnyView(StatusComponent(label: string(props, "label"), status: string(props, "status"), message: props["message"]?.string))
        case .table: return renderTable(props, context: context)
        case .lineChart: return AnyView(LineChartComponent(label: props["label"]?.string ?? "", values: props["values"]?.array ?? [], unit: props["unit"]?.string))
        case .barChart: return AnyView(BarChartComponent(label: props["label"]?.string ?? "", values: props["values"]?.array ?? [], unit: props["unit"]?.string))
        case .textInput, .textArea: return renderTextInput(kind, props, context: context)
        case .numberInput: return renderNumberInput(props, context: context)
        case .select: return renderSelect(props, context: context)
        case .multiSelect: return renderMultiSelect(props, context: context)
        case .toggle: return renderToggle(props, context: context)
        case .slider: return renderSlider(props, context: context)
        case .button: return renderButton(element, props)
        }
    }

    private func renderStack(_ element: PanelElement, context: ExpressionContext, vertical: Bool) -> AnyView {
        let content = element.children.map { render($0, context: context) }
        let gap = CGFloat(element.props["gap"]?.number ?? 12)
        return vertical ? AnyView(VStack(alignment: .leading, spacing: gap) { ForEach(content.indices, id: \.self) { content[$0] } }) : AnyView(HStack(alignment: .center, spacing: gap) { ForEach(content.indices, id: \.self) { content[$0] } })
    }

    private func renderGrid(_ element: PanelElement, context: ExpressionContext, columns: Int) -> AnyView {
        let layout = Array(repeating: GridItem(.flexible()), count: max(1, columns))
        return AnyView(LazyVGrid(columns: layout, spacing: CGFloat(element.props["gap"]?.number ?? 12)) { ForEach(element.children, id: \.self) { render($0, context: context) } })
    }

    private func renderSection(_ element: PanelElement, context: ExpressionContext) -> AnyView {
        let children = AnyView(VStack(alignment: .leading, spacing: 10) { ForEach(element.children, id: \.self) { render($0, context: context) } })
        let label = string(element.props, "label")
        if element.props["collapsible"]?.bool == true { return AnyView(DisclosureGroup(label) { children }) }
        return AnyView(Section(label) { children })
    }

    private func renderRepeat(id: String, element: PanelElement, repeatSpec: RepeatSpec, context: ExpressionContext) -> AnyView {
        guard let values = store.resolve(.object(["$state": .string(repeatSpec.path)]), context: context)?.array else { return AnyView(EmptyView()) }
        let items = values.enumerated().compactMap { pair in
            pair.element.stableID(key: repeatSpec.itemKey).map { RepeatItem(id: $0, index: pair.offset, value: pair.element) }
        }
        return AnyView(VStack(alignment: .leading, spacing: 12) {
            ForEach(items) { item in
                render(id, context: .init(state: .null, item: item.value, index: item.index, itemPath: repeatSpec.path + "/" + String(item.index)))
            }
        })
    }

    private func renderTable(_ props: [String: JSONValue], context: ExpressionContext) -> AnyView {
        let columns = props["columns"]?.array?.compactMap { item -> TableColumnSpec? in
            guard let object = item.object, let id = object["id"]?.string, let label = object["label"]?.string else { return nil }
            return TableColumnSpec(id: id, label: label)
        } ?? []
        let rows = (props["rows"]?.array ?? store.resolve(props["rowsBinding"] ?? .null, context: context)?.array ?? []).enumerated().compactMap { index, value in value.object.map { TableRow(id: index, values: $0) } }
        return AnyView(TableComponent(columns: columns, rows: rows))
    }

    private func renderTextInput(_ kind: ComponentKind, _ props: [String: JSONValue], context: ExpressionContext) -> AnyView {
        let value = store.binding(for: props["value"] ?? .null, context: context) ?? .constant(.string(""))
        return AnyView(TextInputComponent(label: string(props, "label"), value: value, placeholder: props["placeholder"]?.string, multiline: kind == .textArea))
    }

    private func renderNumberInput(_ props: [String: JSONValue], context: ExpressionContext) -> AnyView {
        let value = store.binding(for: props["value"] ?? .null, context: context) ?? .constant(.number(0))
        return AnyView(NumberInputComponent(label: string(props, "label"), value: value, min: props["min"]?.number, max: props["max"]?.number))
    }

    private func renderSelect(_ props: [String: JSONValue], context: ExpressionContext) -> AnyView {
        let value = store.binding(for: props["value"] ?? .null, context: context) ?? .constant(.string(""))
        return AnyView(SelectComponent(label: string(props, "label"), value: value, options: options(props["options"])))
    }

    private func renderMultiSelect(_ props: [String: JSONValue], context: ExpressionContext) -> AnyView {
        let value = store.binding(for: props["value"] ?? .null, context: context) ?? .constant(.array([]))
        return AnyView(MultiSelectComponent(label: string(props, "label"), value: value, options: options(props["options"])))
    }

    private func renderToggle(_ props: [String: JSONValue], context: ExpressionContext) -> AnyView {
        let value = store.binding(for: props["value"] ?? .null, context: context) ?? .constant(.bool(false))
        return AnyView(Toggle(string(props, "label"), isOn: Binding(get: { value.wrappedValue.bool ?? false }, set: { value.wrappedValue = .bool($0) })))
    }

    private func renderSlider(_ props: [String: JSONValue], context: ExpressionContext) -> AnyView {
        let value = store.binding(for: props["value"] ?? .null, context: context) ?? .constant(.number(props["min"]?.number ?? 0))
        let number = Binding(get: { value.wrappedValue.number ?? 0 }, set: { value.wrappedValue = .number($0) })
        return AnyView(VStack(alignment: .leading) { Text(string(props, "label")); Slider(value: number, in: (props["min"]?.number ?? 0)...(props["max"]?.number ?? 1), step: props["step"]?.number ?? 1) })
    }

    private func renderButton(_ element: PanelElement, _ props: [String: JSONValue]) -> AnyView {
        let action = element.on?["press"]
        let button = Button(string(props, "label")) { if let action { onAction(action) } }
        return props["variant"]?.string == "primary" ? AnyView(button.buttonStyle(.borderedProminent)) : AnyView(button.buttonStyle(.bordered))
    }

    private func options(_ value: JSONValue?) -> [PanelOption] {
        value?.array?.compactMap { item in guard let object = item.object, let id = object["id"]?.string, let label = object["label"]?.string else { return nil }; return PanelOption(id: id, label: label, description: object["description"]?.string) } ?? []
    }

    private func string(_ props: [String: JSONValue], _ key: String) -> String { props[key]?.string ?? "" }
    private func resolvedText(_ value: JSONValue?, _ context: ExpressionContext) -> String { value.flatMap { store.resolve($0, context: context) }?.displayText ?? "" }
    private func resolvedNumber(_ value: JSONValue?, _ context: ExpressionContext) -> Double { value.flatMap { store.resolve($0, context: context) }?.number ?? 0 }
    private func textColor(_ tone: String?) -> Color { switch tone { case "muted": return .secondary; case "positive": return Color(nsColor: .systemGreen); case "warning": return Color(nsColor: .systemOrange); case "danger": return Color(nsColor: .systemRed); default: return .primary } }

    private func isVisible(_ expression: JSONValue?, context: ExpressionContext) -> Bool {
        guard let expression else { return true }
        if let boolean = expression.bool { return boolean }
        guard let object = expression.object, let condition = object["$cond"]?.object else { return true }
        guard let path = condition["path"]?.string, let actual = value(at: path, in: store.state) else { return false }
        return condition["value"].map { actual == $0 } ?? false
    }
}

struct ActionStatusView: View {
    let result: PanelActionResult
    var body: some View {
        switch result {
        case .idle: EmptyView()
        case .submitted: Text("Submitted").foregroundStyle(Color(nsColor: .systemGreen))
        case let .opened(panel): Text("Opened \(panel)").foregroundStyle(.secondary)
        case let .rejected(issues): VStack(alignment: .leading) { ForEach(issues.indices, id: \.self) { Text("\(issues[$0].path): \(issues[$0].message)").foregroundStyle(Color(nsColor: .systemRed)).accessibilityLabel("Validation error: \(issues[$0].message)") } }
        }
    }
}

private extension JSONValue {
    func stableID(key: String?) -> String? {
        guard let object else { return nil }
        let key = key ?? "id"
        return object[key]?.string
    }
}

private struct RepeatItem: Identifiable {
    let id: String
    let index: Int
    let value: JSONValue
}
