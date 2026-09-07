// Dynamic fixture values and the small catalog model used by the seam harness.
// Exports: JSONValue, PanelFixture, PanelSpec, PanelElement, and PanelAction.
// Dependencies: Foundation Codable and the mixed-panel fixture.

import Foundation

enum JSONValue: Codable, Equatable, Sendable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Double.self) { self = .number(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([JSONValue].self) { self = .array(value); return }
        self = .object(try container.decode([String: JSONValue].self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    var object: [String: JSONValue]? { if case let .object(value) = self { return value }; return nil }
    var array: [JSONValue]? { if case let .array(value) = self { return value }; return nil }
    var string: String? { if case let .string(value) = self { return value }; return nil }
    var number: Double? { if case let .number(value) = self { return value }; return nil }
    var displayText: String {
        switch self {
        case let .string(value): return value
        case let .number(value): return value.rounded() == value ? String(Int(value)) : String(value)
        case let .bool(value): return value ? "On" : "Off"
        default: return ""
        }
    }
}

struct PanelFixture: Codable, Sendable {
    let title: String
    let formSpec: PanelSpec
    let defaults: JSONValue
    let answerSchema: JSONValue
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
}

struct PanelAction: Codable, Sendable {
    let action: String
    let params: [String: JSONValue]?
}
