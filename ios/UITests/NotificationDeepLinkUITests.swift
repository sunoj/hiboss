// End-to-end coverage for opening a message from a notification-style deep link.
// Exports: NotificationDeepLinkUITests, proving detail loading precedes the current API response.
// Dependencies: XCTest and the app's demo launch environment.

import XCTest

final class NotificationDeepLinkUITests: XCTestCase {
    func testNotificationFromHomeShowsDetailLoadingBeforeContent() {
        let app = XCUIApplication()
        app.configureDemoLaunch([
            "HIBOSS_DEMO_NOTIFICATION_PREVIEW": "c1",
            "HIBOSS_DEMO_HISTORY_DELAY_MS": "60000",
            "HIBOSS_DEMO_REQUESTS_DELAY_MS": "60000",
            "HIBOSS_DEMO_MESSAGE_DELAY_MS": "10000",
        ])
        app.launchConfiguredDemo()

        assertDetailLoading(app, name: "notification-from-home-loading")
        XCTAssertTrue(
            app.staticTexts["message-question"].waitForExistence(timeout: 15),
            "the detail fetch must render without waiting for history or required inputs"
        )
        XCTAssertEqual(app.staticTexts["message-question"].label,
            "Production deploy will DROP 3 history tables (orders_2023 +2), irreversible. Run migration?")
        XCTAssertFalse(app.staticTexts["Loading message…"].exists)
        keepVerifiedScreenshot(app, name: "notification-from-home-content")
    }

    func testNotificationFromProgressShowsDetailLoadingBeforeContent() {
        let app = XCUIApplication()
        app.configureDemoLaunch([
            "HIBOSS_DEMO_NOTIFICATION_OPEN": "c1",
            "HIBOSS_TAB": "progress",
            "HIBOSS_DEMO_HISTORY_DELAY_MS": "60000",
            "HIBOSS_DEMO_REQUESTS_DELAY_MS": "60000",
            "HIBOSS_DEMO_MESSAGE_DELAY_MS": "10000",
        ])
        app.launchConfiguredDemo()

        assertDetailLoading(app, name: "notification-from-progress-loading")
        XCTAssertTrue(
            app.staticTexts["message-question"].waitForExistence(timeout: 15),
            "the detail fetch must render without waiting for history or required inputs"
        )
        XCTAssertEqual(app.staticTexts["message-question"].label,
            "Production deploy will DROP 3 history tables (orders_2023 +2), irreversible. Run migration?")
        XCTAssertFalse(app.staticTexts["Loading message…"].exists)
        keepVerifiedScreenshot(app, name: "notification-from-progress-content")
    }

    private func assertDetailLoading(_ app: XCUIApplication, name: String) {
        XCTAssertTrue(app.navigationBars["Loading…"].waitForExistence(timeout: 2),
            "notification navigation must precede the held message fetch")
        XCTAssertTrue(app.staticTexts["Loading message…"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.tabBars.buttons.element(boundBy: 1).isSelected)
        XCTAssertFalse(app.staticTexts["message-question"].exists,
            "content must still come from the current API")
        keepVerifiedScreenshot(app, name: name)
    }

    private func keepVerifiedScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
