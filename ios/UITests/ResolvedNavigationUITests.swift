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
        XCTAssertTrue(app.staticTexts["4 items waiting on your call"].waitForExistence(timeout: 10))
    }

    func testTwoChoiceDecisionCanBeAnsweredInline() {
        XCTAssertTrue(app.staticTexts["4 items waiting on your call"].waitForExistence(timeout: 10))
        let choice = app.buttons["Coarse grid"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.tap()
        XCTAssertTrue(app.staticTexts["3 items waiting on your call"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["home-message-c5"].exists)
    }

    func testTextAskOpensDetailAndReplyRemovesItFromHome() {
        app.terminate()
        app.configureDemoLaunch(["HIBOSS_DEMO_TEXT_ASK": "1"])
        app.launch()
        XCTAssertTrue(app.staticTexts["1 item waiting on your call"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Nothing needs you"].exists)
        app.buttons["home-message-demo-text-ask"].tap()
        let reply = app.descendants(matching: .any)["message-reply-draft"].firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 5))
        reply.tap()
        reply.typeText("Use staging")
        app.buttons["Send"].tap()
        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.staticTexts["Nothing needs you"].waitForExistence(timeout: 5))
    }

    func testManyOptionsRemainReachableAtAccessibilityTextSize() {
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["4 items waiting on your call"].waitForExistence(timeout: 10))
        let option = app.buttons["Fail over to Adyen"]
        for _ in 0..<12 where !option.isHittable { app.swipeUp() }
        XCTAssertTrue(option.isHittable)
        option.tap()
        for _ in 0..<12 where !app.staticTexts["3 items waiting on your call"].isHittable { app.swipeDown() }
        XCTAssertTrue(app.staticTexts["3 items waiting on your call"].exists)
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
