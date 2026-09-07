// Dynamic protocol values and catalog-shaped fixture models.
// Exports: JSONValue, PanelFixture, PanelSpec, PanelElement, ComponentKind.
// Dependencies: Foundation Codable and Swift standard library.

import Foundation

enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Double.self) { self = .number(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([String: JSONValue].self) { self = .object(value); return }
        self = .array(try container.decode([JSONValue].self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var object: [String: JSONValue]? { if case let .object(value) = self { return value }; return nil }
    var array: [JSONValue]? { if case let .array(value) = self { return value }; return nil }
    var string: String? { if case let .string(value) = self { return value }; return nil }
    var number: Double? { if case let .number(value) = self { return value }; return nil }
    var bool: Bool? { if case let .bool(value) = self { return value }; return nil }

    var displayText: String {
        switch self {
        case let .string(value): return value
        case let .number(value): return value.rounded() == value ? String(Int(value)) : String(value)
        case let .bool(value): return value ? "On" : "Off"
        case .null: return ""
        case .array, .object: return ""
        }
    }
}

enum ComponentKind: String, CaseIterable, Sendable {
    case stack = "Stack", grid = "Grid", section = "Section"
    case text = "Text", metric = "Metric", progress = "Progress", status = "Status", table = "Table"
    case lineChart = "LineChart", barChart = "BarChart"
    case textInput = "TextInput", textArea = "TextArea", numberInput = "NumberInput", select = "Select"
    case multiSelect = "MultiSelect", toggle = "Toggle", slider = "Slider", button = "Button"
}

struct PanelFixture: Codable, Sendable {
    let title: String?
    let spec: PanelSpec?
    let formSpec: PanelSpec?
    let initialState: JSONValue?
    let defaults: JSONValue?
    let answerSchema: JSONValue?
    let context: JSONValue?
    var activeSpec: PanelSpec? { spec ?? formSpec }
    var initialForm: JSONValue { .object(defaults?.object ?? [:]) }
}

struct PanelSpec: Codable, Sendable {
    let root: String
    let elements: [String: PanelElement]
}

struct PanelElement: Codable, Sendable {
    let type: String
    let props: [String: JSONValue]
    let children: [String]
    let on: [String: PanelAction]?
    let visible: JSONValue?
    let repeatSpec: RepeatSpec?

    enum CodingKeys: String, CodingKey { case type, props, children, on, visible, repeatSpec = "repeat" }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        type = try values.decode(String.self, forKey: .type)
        props = try values.decodeIfPresent([String: JSONValue].self, forKey: .props) ?? [:]
        children = try values.decodeIfPresent([String].self, forKey: .children) ?? []
        on = try values.decodeIfPresent([String: PanelAction].self, forKey: .on)
        visible = try values.decodeIfPresent(JSONValue.self, forKey: .visible)
        repeatSpec = try values.decodeIfPresent(RepeatSpec.self, forKey: .repeatSpec)
    }
}

struct RepeatSpec: Codable, Sendable {
    let path: String
    let itemKey: String?
}

struct PanelAction: Codable, Sendable {
    let action: String
    let params: [String: JSONValue]?
}
