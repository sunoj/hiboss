// Derives a stable dashboard summary from authored components and current state.
// Exports: PanelDashboardContent, PanelDashboardSeries, and PanelDashboardProgress.
// Dependencies: PanelFixture, PanelValue, and the display binding resolver.

import Foundation

public struct PanelDashboardSeries {
    public let label: String
    public let unit: String?
    public let values: [Double?]
    public let isBar: Bool
}

public struct PanelDashboardProgress {
    public let label: String
    public let fraction: Double
}

public struct PanelDashboardContent {
    public let metrics: [PanelHeadline]
    public let progress: PanelDashboardProgress?
    public let series: PanelDashboardSeries?
    let table: [String: PanelValue]?
    let fields: [String]
    let stage: String?

    public init(fixture: PanelFixture, state: PanelValue) {
        let elements = Self.orderedElements(in: fixture.spec)
        var headlines = [fixture.summary?.headline, fixture.summary?.secondary].compactMap { $0 }
        for element in elements where element.type == "Metric" {
            guard let value = element.props["value"] else { continue }
            let headline = PanelHeadline(
                path: value.object?["$state"]?.string, literal: value,
                label: element.props["label"]?.string ?? "Metric", unit: element.props["unit"]?.string
            )
            if !headlines.contains(where: { $0.path == headline.path && $0.label == headline.label }) {
                headlines.append(headline)
            }
        }
        metrics = Array(headlines.prefix(3))
        progress = Self.progress(in: elements, state: state)
        let display = fixture.wallDisplayDefinition.map { resolvedWebLeafDefinition($0, state: state) }
        table = display?["type"]?.string == "Table" ? display : nil
        series = Self.series(fixture: fixture, display: display, state: state)
        fields = elements.filter { Self.inputTypes.contains($0.type) }.map { $0.props["label"]?.string ?? $0.type }
        stage = fixture.summary?.stage ?? elements.first(where: { $0.type == "Status" })?.props["message"]?.string
    }

    private static let inputTypes: Set<String> = [
        "TextInput", "TextArea", "NumberInput", "Select", "MultiSelect", "Toggle", "Slider"
    ]

    private static func orderedElements(in spec: PanelSpec) -> [PanelElement] {
        var pending = [spec.root]
        var visited = Set<String>()
        var result: [PanelElement] = []
        while let id = pending.popLast() {
            guard visited.insert(id).inserted, let element = spec.elements[id] else { continue }
            result.append(element)
            pending.append(contentsOf: element.children.reversed())
        }
        return result
    }

    private static func progress(in elements: [PanelElement], state: PanelValue) -> PanelDashboardProgress? {
        guard let element = elements.first(where: { $0.type == "Progress" }) else { return nil }
        let props = resolvedWebLeafDefinition(element.props, state: state)
        guard let value = props["value"]?.number, value.isFinite else { return nil }
        let minimum = props["min"]?.number ?? 0
        let maximum = props["max"]?.number ?? 1
        guard minimum.isFinite, maximum.isFinite, maximum > minimum else { return nil }
        return PanelDashboardProgress(
            label: props["label"]?.string ?? "Progress",
            fraction: min(1, max(0, (value - minimum) / (maximum - minimum)))
        )
    }

    private static func series(
        fixture: PanelFixture, display: [String: PanelValue]?, state: PanelValue
    ) -> PanelDashboardSeries? {
        if let path = fixture.summary?.seriesPath {
            let values = panelValue(at: path, in: state)?.array ?? []
            return PanelDashboardSeries(label: "Trend", unit: nil, values: values.map(\.number), isBar: false)
        }
        guard let display, ["LineChart", "BarChart"].contains(display["type"]?.string) else { return nil }
        return PanelDashboardSeries(
            label: display["label"]?.string ?? "Trend", unit: display["unit"]?.string,
            values: (display["values"]?.array ?? []).map { value in
                guard let number = value.number, number.isFinite else { return nil }
                return number
            }, isBar: display["type"]?.string == "BarChart"
        )
    }
}
