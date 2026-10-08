// Exercises failed Home with cached budget metrics through the configured demo launch.
// Exports HomePanelLayoutUITests and named Home screenshots for light/dark and text sizes.
// Dependencies: IntermediateCaptureCase and the demo panel discovery timeout.

import XCTest

final class HomePanelLayoutUITests: IntermediateCaptureCase {
    private func launchFailedHome() {
        launch(["HIBOSS_DEMO_EMPTY": "1", "HIBOSS_DEMO_CONNECTION": "failed",
                "HIBOSS_DEMO_METRIC_PANEL": "1"])
        XCTAssertTrue(app.staticTexts["home-connection-status"].waitForExistence(timeout: 10))
    }

    func testFailureSuppressesSlowWaitCopy() {
        launchFailedHome()
        pause(9)
        XCTAssertFalse(app.staticTexts["This is taking longer than expected."].exists)
        XCTAssertTrue(app.buttons["pending-retry"].firstMatch.exists)
        capture("home-metric-failure")
    }

    func testRecoveryButtonsUseTheSameNativeHeight() {
        launchFailedHome()
        let retry = app.buttons["pending-retry"].firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 12))
        let settings = app.scrollViews.buttons["Settings"].firstMatch
        XCTAssertEqual(retry.frame.height, settings.frame.height, accuracy: 1)
        XCTAssertGreaterThanOrEqual(settings.frame.height, 44)
    }

    func testCachedPanelDoesNotRepeatTheConnectionError() {
        launchFailedHome()
        pause(6)
        pullToRefresh(app)
        pause(2)
        XCTAssertFalse(app.staticTexts["The request timed out."].exists)
        let metric = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '8,438,950'")).firstMatch
        reveal(metric)
        XCTAssertTrue(metric.isHittable)
        XCTAssertTrue(app.staticTexts["Offline"].exists)
        capture("home-cached-metrics")
    }

    func testHomeMetricScreenshots() {
        launchFailedHome()
        pause(6)
        pullToRefresh(app)
        pause(2)
        capture("home-metrics-top")
        let construction = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '8,438,950'"))
            .firstMatch
        reveal(construction)
        capture("home-metrics-panel")
        let systems = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '1,068,560'"))
            .firstMatch
        reveal(systems)
        capture("home-metrics-panel-bottom")
        for value in ["8,438,950", "4,554,994", "1,068,560"] {
            XCTAssertTrue(app.staticTexts[value + " THB"].exists)
        }
        XCTAssertFalse(app.staticTexts["This is taking longer than expected."].exists)
        XCTAssertFalse(app.staticTexts["The request timed out."].exists)
    }
}
