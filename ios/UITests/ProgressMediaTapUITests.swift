// UI coverage for tapping progress-feed media into the full-screen viewer.
// Exports: ProgressMediaTapUITests.
// Dependencies: XCTest.

import XCTest

final class ProgressMediaTapUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HIBOSS_DEMO"] = "1"
        app.launchEnvironment["HIBOSS_TAB"] = "progress"
        app.launch()
    }

    func testTappingFeedImageOpensFullScreenViewer() {
        let image = app.images["wide landscape screenshot"]
        XCTAssertTrue(image.waitForExistence(timeout: 8), "demo feed image should appear")
        image.tap()

        XCTAssertTrue(
            app.buttons["Close"].waitForExistence(timeout: 3),
            "full-screen viewer should present after tapping the feed image"
        )
    }
}
