// UI coverage for navigating out of the handled-decisions screen.
// Exports: ResolvedNavigationUITests.
// Dependencies: XCTest.

import XCTest

/// Regression: an `isPresented`-based `navigationDestination` on the Inbox swallowed every
/// later value push, so tapping a row inside Resolved re-opened Resolved instead of the
/// message it names. Every existing test passed while that was true, because none of them
/// entered the screen and then tapped a row — the first thing a real reader does.
final class ResolvedNavigationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HIBOSS_DEMO"] = "1"
        app.launchEnvironment["HIBOSS_DEMO_RESOLVED"] = "1"
        app.launch()
    }

    func testTappingAResolvedRowLeavesTheResolvedScreen() {
        let resolvedBar = app.navigationBars["Resolved"]
        XCTAssertTrue(resolvedBar.waitForExistence(timeout: 10), "demo route should open Resolved")

        let row = app.buttons.containing(.staticText, identifier: "Ship").firstMatch
        let target = row.exists ? row : app.cells.firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 8), "Resolved should list handled decisions")
        target.tap()

        // The bug reproduced as "still on Resolved". Assert we left it, rather than
        // asserting a specific destination title — the point is not re-entering itself.
        XCTAssertTrue(
            resolvedBar.waitForNonExistence(timeout: 8),
            "tapping a handled decision must not re-open Resolved"
        )
    }
}
