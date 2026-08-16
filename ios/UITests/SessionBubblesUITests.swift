// UI coverage for SMS-style session bubbles and centred system lines.
// Exports: SessionBubblesUITests.
// Dependencies: XCTest, DemoLaunchSupport.

import XCTest

final class SessionBubblesUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.configureDemoLaunch(["HIBOSS_DEMO_SESSION": "1"])
        app.launch()
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
        XCTAssertTrue(
            app.descendants(matching: .any)["session-system-line"].exists,
            "non-message events must render as centred system lines"
        )
        XCTAssertTrue(app.buttons["Show more"].exists, "long tool output must offer expand")
    }
}
