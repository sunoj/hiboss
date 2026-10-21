// Settings → Notifications per server push mode: `none` explains itself and offers no prompt,
// `relay` says Live Activities update only while the app is open.
// Exports: PushModeUITests. Dependencies: XCTest, DemoLaunchSupport (HIBOSS_DEMO_PUSH_MODE).

import XCTest

final class PushModeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func openNotifications(mode: String) {
        app.configureDemoLaunch(["HIBOSS_DEMO_PUSH_MODE": mode])
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchConfiguredDemo()
        XCTAssertTrue(app.buttons["today-settings"].waitForExistence(timeout: 8))
        app.buttons["today-settings"].tap()
        XCTAssertTrue(app.buttons["settings-notifications"].waitForExistence(timeout: 5))
        app.buttons["settings-notifications"].tap()
    }

    func testNoneModeExplainsAndOffersNoPermissionPrompt() {
        openNotifications(mode: "none")
        let notice = app.descendants(matching: .any)["settings-push-unavailable"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(
            format: "label CONTAINS %@", "turned off the HiBoss push relay")).firstMatch.exists)
        XCTAssertFalse(app.buttons["Enable Notifications"].exists)
        XCTAssertFalse(app.buttons["Open Settings to Enable"].exists)
        XCTAssertFalse(app.staticTexts["Enable notifications above to receive phone alerts."].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "en-push-mode-none"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testRelayModeSaysLiveActivitiesNeedTheAppOpen() {
        openNotifications(mode: "relay")
        let help = app.staticTexts.containing(NSPredicate(
            format: "label CONTAINS %@", "Live Activities update only while HiBoss is open")).firstMatch
        XCTAssertTrue(help.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["settings-push-unavailable"].exists)
    }
}
