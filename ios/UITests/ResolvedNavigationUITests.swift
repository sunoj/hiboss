// UI coverage for Home attention states and handled-decision navigation.
// Exports: HomeAttentionUITests, ResolvedNavigationUITests.
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
        app.configureDemoLaunch(["HIBOSS_DEMO_RESOLVED": "1"])
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

final class HomeAttentionUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.configureDemoLaunch()
        app.launch()
    }

    func testPopulatedDemoShowsAttentionCount() {
        XCTAssertTrue(app.staticTexts["3 items waiting on your call"].waitForExistence(timeout: 10))
    }

    func testEmptyDemoShowsSettledAnswer() {
        app.terminate()
        app = XCUIApplication()
        app.configureDemoLaunch(["HIBOSS_DEMO_EMPTY": "1"])
        app.launch()

        XCTAssertTrue(app.staticTexts["Nothing needs you"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Everything is settled. This is where an agent's next question will appear."].exists)
    }
}
