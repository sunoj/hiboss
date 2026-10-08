// UI coverage for session bubbles, collapsed step runs, and decisions answered in the transcript.
// Exports: SessionBubblesUITests.
// Dependencies: XCTest, DemoLaunchSupport.

import XCTest

final class SessionBubblesUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.configureDemoLaunch(["HIBOSS_DEMO_SESSION": "1"])
        app.launchConfiguredDemo()
    }

    func testSessionDetailShowsBubblesAndSystemLines() {
        XCTAssertTrue(
            app.navigationBars["prod-release"].waitForExistence(timeout: 10),
            "demo session route should open the prod-release transcript"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["session-bubble-incoming"].waitForExistence(timeout: 8),
            "agent messages must render as incoming bubbles"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["session-bubble-outgoing"].exists,
            "boss messages must render as outgoing bubbles"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["session-system-line"].exists,
            "tool calls, results and hooks stay collapsed until the boss asks"
        )
        XCTAssertFalse(app.staticTexts["future_kind · kept by fallback"].exists, "unknown kinds are never shown raw")
        let steps = app.buttons["session-steps"].firstMatch
        XCTAssertTrue(steps.waitForExistence(timeout: 5), "activity collapses into one steps row")
        XCTAssertTrue(steps.label.contains("3 steps"), "known activity is counted, got \(steps.label)")
        steps.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["session-system-line"].waitForExistence(timeout: 5),
            "expanding the run shows each step's detail"
        )
        XCTAssertTrue(app.buttons["Show more"].exists, "long tool output must offer expand")
    }

    func testPendingDecisionIsAnsweredInPlace() {
        let card = app.descendants(matching: .any)["transcript-decision-c1"]
        XCTAssertTrue(card.waitForExistence(timeout: 10), "the pending migration decision renders as a decision card")
        XCTAssertTrue(app.descendants(matching: .any)["decision-timing-c1"].exists, "same timing line as Home")
        let approve = card.buttons["Approve"]
        XCTAssertTrue(approve.waitForExistence(timeout: 5), "options are answerable from the transcript")
        approve.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["transcript-answer-c1"].waitForExistence(timeout: 8),
            "the answered decision shows its answer in place"
        )
        XCTAssertFalse(card.buttons["Approve"].exists, "options leave once answered")
        XCTAssertTrue(
            app.descendants(matching: .any)["transcript-answer-c0"].exists,
            "an earlier decision shows the recorded answer"
        )
    }
}
