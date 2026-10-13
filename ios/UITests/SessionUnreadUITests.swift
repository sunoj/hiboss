// Verifies local session unread dots, read-on-open, stable rows and demo appearance.
// Exports SessionUnreadUITests for the Sessions and Today session lists.
// Dependencies: XCTest and launchConfiguredDemo.

import XCTest

@MainActor
final class SessionUnreadUITests: XCTestCase {
    func testOpeningUnreadSessionClearsDotWithoutMovingRow() {
        let app = launch()
        app.tabBars.buttons["Sessions"].tap()
        let row = app.buttons["activity-session-read-unread"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("Unread"))
        let frame = row.frame
        row.tap()
        XCTAssertTrue(app.buttons["Message history"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertFalse(row.label.contains("Unread"))
        XCTAssertEqual(row.frame, frame)
    }

    func testLightSessionStates() { capture("Light") }
    func testDarkSessionStates() { capture("Dark") }

    func testAccessibilitySessionStates() {
        let app = launch("Light", largeText: true)
        app.tabBars.buttons["Sessions"].tap()
        let row = app.buttons["activity-session-read-unread"]
        for _ in 0..<5 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("Unread"))
        shot(app, "sessions-ax")
        app.tabBars.buttons["Today"].tap()
        for _ in 0..<5 where !app.staticTexts["Working now"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["Working now"].exists)
        shot(app, "today-ax")
    }

    private func launch(_ appearance: String = "Light", largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.configureDemoLaunch(["HIBOSS_DEMO_SESSION_READS": "1"])
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-AppleInterfaceStyle", appearance]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName",
                                    "UICTContentSizeCategoryAccessibilityL"]
        }
        app.launchConfiguredDemo()
        return app
    }

    private func capture(_ appearance: String) {
        let app = launch(appearance)
        app.tabBars.buttons["Sessions"].tap()
        let unread = app.buttons["activity-session-read-unread"]
        XCTAssertTrue(unread.waitForExistence(timeout: 10))
        XCTAssertTrue(unread.label.contains("Unread"))
        XCTAssertFalse(app.buttons["activity-session-read-needs"].label.contains("Unread"))
        XCTAssertTrue(app.buttons["activity-session-read-needs"].label.contains("Needs you"))
        XCTAssertTrue(app.buttons["activity-session-read-working"].label.contains("Working"))
        XCTAssertFalse(app.buttons["activity-session-read-idle"].label.contains("Unread"))
        shot(app, "sessions-\(appearance)")
        app.tabBars.buttons["Today"].tap()
        for _ in 0..<5 where !app.staticTexts["Working now"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["Working now"].exists)
        shot(app, "today-\(appearance)")
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        captureDemoScreenshot(app, name: name, test: self)
    }
}
