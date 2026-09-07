// Typed fixture metadata layered over the shared panel-runtime contracts.
// Exports: PanelFixture, PanelSummary, and PanelHeadline.
// Dependencies: Foundation and HibossKit panel API contracts.

import Foundation

public struct PanelFixture: Sendable {
    public let name: String
    public let title: String
    public let summary: PanelSummary?
    public let spec: PanelSpec
    public let initialState: PanelValue

    public init(name: String, data: Data) throws {
        let raw = try JSONDecoder().decode(RawFixture.self, from: data)
        guard let spec = raw.formSpec ?? raw.spec else { throw PanelFixtureError.missingSpec }
        self.name = name
        self.title = raw.title ?? Self.defaultTitle(for: name)
        self.summary = raw.summary.flatMap(PanelSummary.init(value:))
        self.spec = spec
        self.initialState = raw.formSpec == nil
            ? raw.initialState ?? .object([:])
            : .object(["form": raw.defaults ?? .object([:])])
    }

    public init(remote panel: PanelDetail) {
        name = panel.metadata.panelId
        title = panel.metadata.title
        summary = PanelSummary(value: panel.metadata.summary)
        spec = panel.definition.spec
        initialState = panel.definition.initialState
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
        let defaults: PanelValue?
        let initialState: PanelValue?
        let summary: PanelValue?
        let formSpec: PanelSpec?
        let spec: PanelSpec?
    }
}

public struct PanelHeadline: Equatable, Sendable {
    public let path: String?
    public let literal: PanelValue?
    public let label: String
    public let unit: String?

    public func displayValue(in state: PanelValue) -> String {
        if let path { return panelValue(at: path, in: state)?.displayText ?? "—" }
        return literal?.displayText ?? "—"
    }
}

public struct PanelSummary: Equatable, Sendable {
    public let stage: String
    public let headline: PanelHeadline?
    public let secondary: PanelHeadline?
    public let seriesPath: String?

    public init?(value: PanelValue) {
        guard let object = value.object, let stage = object["stage"]?.string else { return nil }
        self.stage = stage
        headline = Self.headline(object["headline"])
        secondary = Self.headline(object["secondary"])
        seriesPath = object["series"]?.string
    }

    private static func headline(_ value: PanelValue?) -> PanelHeadline? {
        guard let object = value?.object, let path = object["path"]?.string, let label = object["label"]?.string else { return nil }
        return PanelHeadline(path: path, literal: nil, label: label, unit: object["unit"]?.string)
    }
}

extension PanelFixture {
    public var firstMetricHeadline: PanelHeadline? {
        for element in spec.elements.values where element.type == "Metric" {
            let label = element.props["label"]?.string ?? "Metric"
            let unit = element.props["unit"]?.string
            if let path = element.props["value"]?.object?["$state"]?.string {
                return PanelHeadline(path: path, literal: nil, label: label, unit: unit)
            }
            if let literal = element.props["value"] { return PanelHeadline(path: nil, literal: literal, label: label, unit: unit) }
        }
        return nil
    }
}

public enum PanelFixtureError: Error { case missingSpec }
