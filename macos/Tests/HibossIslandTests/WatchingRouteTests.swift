// Verifies where opened panels go and which panels Today and the sidebar count as running.
// Exports: WatchingRouteTests (logic only; opens no windows).
// Dependencies: XCTest, HibossKit demo PanelsModel, and WatchingRoute.

import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class WatchingRouteTests: XCTestCase {
    func testOpeningAPanelShowsWatchingExceptInsideASessionThread() {
        for origin: OverviewDestination in [.today, .progress, .box, .deviceRequests, .category(.all)] {
            XCTAssertEqual(WatchingRoute.destination(openingPanelFrom: origin), .watching, "\(origin)")
        }
        XCTAssertNil(WatchingRoute.destination(openingPanelFrom: .watching))
        XCTAssertNil(WatchingRoute.destination(openingPanelFrom: .session("hiboss/main")))
    }

    func testRunningExcludesFinishedAndArchivedPanels() {
        let tiles = PanelsModel(demoMode: true, autoload: false).tiles
        let running = WatchingRoute.running(tiles)
        XCTAssertFalse(running.isEmpty)
        XCTAssertTrue(running.allSatisfy { !$0.lifecycle.taskState.isTerminal })
        XCTAssertTrue(running.allSatisfy { $0.preference.placement != .archived })
        let excluded = tiles.filter { tile in !running.contains { $0.id == tile.id } }
        XCTAssertTrue(excluded.allSatisfy {
            $0.lifecycle.taskState.isTerminal || $0.preference.placement == .archived
        }, "Only finished or archived panels may be left out")
    }
}
