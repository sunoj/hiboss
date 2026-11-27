// Verifies what the toolbar Live chip says for each connection and refresh state.
// Exports: ToolbarLiveChipTests (pure logic; opens no windows).
// Dependencies: XCTest, HibossKit ConnectionState, and the production chip policy.

import HibossKit
import XCTest
@testable import HibossIsland

final class ToolbarLiveChipTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testLiveChipCarriesTheAgeOfTheLastLoad() {
        let state = ToolbarLiveChip.State.of(.connected, updatedAt: now.addingTimeInterval(-6),
            showsUpdating: false, failure: nil)
        XCTAssertEqual(state.text(now: now), L("Live · updated \(AttentionClock.elapsed(since: now.addingTimeInterval(-6), now: now, coarse: true)) ago"))
        XCTAssertEqual(state.tone, .live)
        XCTAssertEqual(ToolbarLiveChip.State.of(.connected, updatedAt: nil, showsUpdating: false,
            failure: nil).text(now: now), L("Live"))
    }

    func testFailureWinsOverConnectionAndANonLiveConnectionIsNamed() {
        XCTAssertEqual(ToolbarLiveChip.State.of(.connected, updatedAt: now, showsUpdating: true,
            failure: "500").tone, .failed)
        let failed = ToolbarLiveChip.State.of(.failed("401"), updatedAt: now, showsUpdating: false, failure: nil)
        XCTAssertEqual(failed.text(now: now), ConnectionState.failed("401").label)
        XCTAssertEqual(failed.tone, .quiet)
        XCTAssertEqual(ToolbarLiveChip.State.of(.connected, updatedAt: now, showsUpdating: true,
            failure: nil), .updating)
    }
}
