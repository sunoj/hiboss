// Typed panel fixture models and JSON values used by the native panel renderer.
// Exports: PanelJSONValue, PanelFixture, PanelSpec, PanelElement, and PanelAction.
// Dependencies: Foundation Codable and the shared panel-runtime fixture shape.

import Foundation
import HibossKit

enum PanelJSONValue: Codable, Equatable, Sendable {
    case null, bool(Bool), number(Double), string(String), array([PanelJSONValue]), object([String: PanelJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Double.self) { self = .number(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([PanelJSONValue].self) { self = .array(value); return }
        self = .object(try container.decode([String: PanelJSONValue].self))
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

    var object: [String: PanelJSONValue]? { if case let .object(value) = self { value } else { nil } }
    var array: [PanelJSONValue]? { if case let .array(value) = self { value } else { nil } }
    var string: String? { if case let .string(value) = self { value } else { nil } }
    var number: Double? { if case let .number(value) = self { value } else { nil } }
    var bool: Bool? { if case let .bool(value) = self { value } else { nil } }

    var displayText: String {
        switch self {
        case let .string(value): value
        case let .number(value): value.rounded() == value ? String(Int(value)) : String(value)
        case let .bool(value): value ? "On" : "Off"
        default: ""
        }
    }
}

struct PanelFixture: Sendable {
    let name: String
    let title: String
    let spec: PanelSpec
    let initialState: PanelJSONValue

    init(name: String, data: Data) throws {
        let raw = try JSONDecoder().decode(RawFixture.self, from: data)
        guard let spec = raw.formSpec ?? raw.spec else { throw PanelFixtureError.missingSpec }
        self.name = name
        self.title = raw.title ?? Self.defaultTitle(for: name)
        self.spec = spec
        self.initialState = raw.formSpec == nil
            ? raw.initialState ?? .object([:])
            : .object(["form": raw.defaults ?? .object([:])])
    }

    init(remote panel: PanelDetail) {
        name = panel.metadata.panelId
        title = panel.metadata.title
        spec = PanelSpec(remote: panel.definition.spec)
        initialState = PanelJSONValue(remote: panel.definition.initialState)
    }

    private static func defaultTitle(for name: String) -> String {
        switch name {
        case "download-progress.json": return "Nightly artifact transfer"
        case "e2e-test-run.json": return "Checkout journey tests"
        case "benchmark-sweep.json": return "Image pipeline benchmark"
        case "service-monitor.json": return "Production image API monitor"
        default: return "Metric fixture"
        }
    }

    private struct RawFixture: Decodable {
        let title: String?
        let defaults: PanelJSONValue?
        let initialState: PanelJSONValue?
        let formSpec: PanelSpec?
        let spec: PanelSpec?
    }
}

private extension PanelSpec {
    init(remote spec: HibossKit.PanelSpec) {
        root = spec.root
        elements = spec.elements.mapValues(PanelElement.init(remote:))
    }
}

private extension PanelElement {
    init(remote element: HibossKit.PanelElement) {
        type = element.type
        props = element.props.mapValues(PanelJSONValue.init(remote:))
        children = element.children
        on = element.on?.mapValues(PanelAction.init(remote:))
    }
}

private extension PanelAction {
    init(remote action: HibossKit.PanelAction) {
        self.action = action.action
        params = action.params?.mapValues(PanelJSONValue.init(remote:))
    }
}

extension PanelJSONValue {
    init(remote value: HibossKit.PanelValue) {
        switch value {
        case .null: self = .null
        case let .bool(value): self = .bool(value)
        case let .number(value): self = .number(value)
        case let .string(value): self = .string(value)
        case let .array(value): self = .array(value.map(PanelJSONValue.init(remote:)))
        case let .object(value): self = .object(value.mapValues(PanelJSONValue.init(remote:)))
        }
    }
}

enum PanelFixtureError: Error { case missingSpec }

struct PanelSpec: Decodable, Sendable {
    let root: String
    let elements: [String: PanelElement]
}

struct PanelElement: Decodable, Sendable {
    let type: String
    let props: [String: PanelJSONValue]
    let children: [String]
    let on: [String: PanelAction]?
}

struct PanelAction: Decodable, Sendable {
    let action: String
    let params: [String: PanelJSONValue]?
}
