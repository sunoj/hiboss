// Verifies that bound chart data reaches the shared display leaf as a series.
// Exports: PanelWebLeafTests.
// Dependencies: XCTest, PanelValue, and the shared web-leaf resolver.

import XCTest
@testable import HibossKit

final class PanelWebLeafTests: XCTestCase {
    func testBoundChartResolvesItsSeriesFromStateBeforeRendering() {
        let definition: [String: PanelValue] = [
            "type": .string("LineChart"),
            "values": .object(["$state": .string("/task/series")]),
        ]
        let state: PanelValue = .object([
            "task": .object(["series": .array([.number(12), .null, .number(18)])]),
        ])

        let rendered = resolvedWebLeafDefinition(definition, state: state)

        XCTAssertEqual(rendered["values"], .array([.number(12), .null, .number(18)]))
    }

    func testLiteralChartValuesAndNullGapsRemainUnchanged() {
        let definition: [String: PanelValue] = [
            "type": .string("LineChart"),
            "values": .array([.number(4), .null, .number(9)]),
        ]

        let rendered = resolvedWebLeafDefinition(definition, state: .object([:]))

        XCTAssertEqual(rendered, definition)
    }
}
