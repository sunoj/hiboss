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

    func testWallDisplayDefinitionFindsChartWithoutSummaryMetadata() throws {
        let fixture = try XCTUnwrap(
            PanelExampleFixtures.load().first { $0.name == "download-progress.json" }
        )

        XCTAssertNil(fixture.summary)
        XCTAssertEqual(fixture.wallDisplayDefinition?["type"], .string("LineChart"))
        XCTAssertEqual(
            fixture.wallDisplayDefinition?["values"],
            .array([.number(142), .number(156), .number(171), .null, .number(184),
                    .number(179), .number(191), .number(188), .number(196), .number(202)])
        )
    }
}
