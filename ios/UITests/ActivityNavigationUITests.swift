// Covers the merged history browser, direct Home session links and offline empty states.
// Exports: ActivityNavigationUITests with screenshots of each changed interaction.
// Dependencies: XCTest and DemoLaunchSupport.

import XCTest

final class ActivityNavigationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ extra: [String: String] = [:]) {
        app.configureDemoLaunch(extra)
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchConfiguredDemo()
    }

    func testActivityCombinesSessionsAndMessagesAndRemembersSelection() {
        launch()
        XCTAssertTrue(app.tabBars.buttons["Activity"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.tabBars.buttons.count, 4)
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.buttons["activity-session-sess-deploy"].waitForExistence(timeout: 5))
        screenshot("activity-sessions")
        app.buttons["activity-session-sess-deploy"].tap()
        XCTAssertTrue(app.navigationBars["prod-release"].waitForExistence(timeout: 5))
        screenshot("activity-transcript")
        app.navigationBars.buttons.firstMatch.tap()
        app.segmentedControls.buttons["Messages"].tap()
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 5))
        screenshot("activity-messages")
        app.tabBars.buttons["Home"].tap()
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["Messages"].isSelected)
    }

    func testHomeSessionMenuOpensTranscriptWithoutOpeningDetail() {
        launch()
        let row = app.buttons["home-message-c5"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.press(forDuration: 1)
        let session = app.buttons["home-session-c5"]
        XCTAssertTrue(session.waitForExistence(timeout: 10))
        session.tap()
        XCTAssertTrue(app.navigationBars["prod-release"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["message-question"].exists)
        XCTAssertTrue(app.tabBars.buttons["Home"].isSelected)
        screenshot("home-direct-transcript")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }

    func testUnhealthyEmptyHomeNeverClaimsAllClear() {
        for state in ["failed", "connecting", "disconnected"] {
            launch(["HIBOSS_DEMO_EMPTY": "1", "HIBOSS_DEMO_CONNECTION": state])
            let status = app.staticTexts["home-connection-status"]
            XCTAssertTrue(status.waitForExistence(timeout: 10), state)
            XCTAssertFalse(app.staticTexts["Nothing needs you"].exists, state)
            XCTAssertFalse(app.staticTexts["Nothing is waiting on your call"].exists, state)
            screenshot("empty-\(state)")
            app.terminate()
        }
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = (ProcessInfo.processInfo.environment["UX_TOUR_PREFIX"] ?? "") + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
