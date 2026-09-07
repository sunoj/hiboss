// Proves the Panels wall arrangement is deterministic and independent of data updates.
// Exports: PanelWallLayoutTests for stable packing, append-only slots, and reflow.
// Dependencies: XCTest and the pure PanelWallLayout module.

import XCTest
@testable import HibossIsland

final class PanelWallLayoutTests: XCTestCase {
    private let panels = [
        PanelLayoutPanel(id: "alpha", size: .compact, order: 0, isPinned: false),
        PanelLayoutPanel(id: "bravo", size: .wide, order: 1, isPinned: false),
        PanelLayoutPanel(id: "charlie", size: .compact, order: 2, isPinned: false),
    ]

    func testSamePanelsAtSameWidthProduceTheSameArrangement() {
        let first = PanelWallLayout.arrange(panels, width: 760)
        let second = PanelWallLayout.arrange(panels, width: 760)

        XCTAssertEqual(first, second)
    }

    @MainActor func testDataUpdateLeavesEveryPositionIdentical() {
        // Driving the real model, because arrange() cannot see data by construction and
        // calling it twice with identical arguments would assert f(x) == f(x).
        let model = PanelsModel(demoMode: true)
        try? XCTSkipIf(model.tiles.isEmpty, "fixtures unavailable")
        let before = model.positions(for: 760)
        XCTAssertFalse(before.isEmpty)

        for (index, tile) in model.tiles.enumerated() {
            tile.store.setNumber(Double(index * 37 + 5), at: "/task/completed")
            tile.store.setString("pushed-\(index)", at: "/task/stage")
        }

        XCTAssertEqual(model.positions(for: 760), before, "a producer push must not move any tile")
    }

    func testLaterTileChangingSizeDoesNotMoveEarlierTiles() {
        let before = PanelWallLayout.arrange(panels, width: 760)
        let changedLaterTile = [
            panels[0],
            panels[1],
            PanelLayoutPanel(id: "charlie", size: .wide, order: 2, isPinned: false),
        ]
        let after = PanelWallLayout.arrange(changedLaterTile, width: 760)

        XCTAssertEqual(before[0], after[0])
        XCTAssertEqual(before[1], after[1])
    }

    func testWidthChangeCanReflowTheWall() {
        let wide = PanelWallLayout.arrange(panels, width: 760)
        let narrow = PanelWallLayout.arrange(panels, width: 520)

        XCTAssertNotEqual(wide, narrow)
    }
}
