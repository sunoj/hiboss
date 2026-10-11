// Exercises cold Today coverage using equal deterministic demo source latencies.
// Exports TodayStartupUITests; startup OSLog lines provide process-relative timing.
// Dependencies: XCTest and launchConfiguredDemo.

import XCTest

@MainActor
final class TodayStartupUITests: XCTestCase {
    func testLoadingQuestionnairesCannotShowLiveOrAllClear() {
        let app = XCUIApplication()
        app.configureDemoLaunch([
            "HIBOSS_DEMO_EMPTY": "1", "HIBOSS_DEMO_QUESTIONNAIRES_DELAY_MS": "60000"
        ])
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchConfiguredDemo()
        XCTAssertTrue(app.staticTexts["Checking coverage"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Nothing needs you"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Live'")).firstMatch.exists)
        app.terminate()
    }

    func testDelayedSourcesSettleWithoutPrematureAllClear() {
        let app = XCUIApplication()
        app.configureDemoLaunch([
            "HIBOSS_DEMO_EMPTY": "1",
            "HIBOSS_DEMO_HISTORY_DELAY_MS": "1200",
            "HIBOSS_DEMO_REQUESTS_DELAY_MS": "1200",
            "HIBOSS_DEMO_REQUESTS_READY_DELAY_MS": "300",
            "HIBOSS_DEMO_PANELS_DELAY_MS": "1200",
            "HIBOSS_DEMO_QUESTIONNAIRES_DELAY_MS": "1200"
        ])
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchConfiguredDemo()
        XCTAssertTrue(app.staticTexts["Nothing needs you"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Checking coverage"].exists)
        app.terminate()
    }
}
