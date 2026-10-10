// End-to-end coverage for opening a message from a notification-style deep link.
// Exports: NotificationDeepLinkUITests, proving push snapshots wait for account verification.
// Dependencies: XCTest and the app's demo launch environment.

import XCTest

final class NotificationDeepLinkUITests: XCTestCase {
    func testCurrentProductionNotificationVerifiesAlertBodyBeforeShowingIt() {
        let app = XCUIApplication()
        app.configureDemoLaunch([
            "HIBOSS_DEMO_NOTIFICATION_PREVIEW": "c1",
            "HIBOSS_DEMO_HISTORY_DELAY_MS": "10000",
            "HIBOSS_DEMO_MESSAGE_DELAY_MS": "10000",
        ])
        app.launchConfiguredDemo()

        XCTAssertFalse(app.staticTexts["message-question"].waitForExistence(timeout: 2))
        XCTAssertTrue(
            app.staticTexts["message-question"].waitForExistence(timeout: 15),
            "the notification must render after the current API verifies it"
        )
        XCTAssertEqual(app.staticTexts["message-question"].label,
            "Production deploy will DROP 3 history tables (orders_2023 +2), irreversible. Run migration?")
        keepVerifiedScreenshot(app, name: "verified-notification-preview")
    }

    func testCompleteNotificationSnapshotWaitsForCurrentMessageAPI() {
        let app = XCUIApplication()
        app.configureDemoLaunch([
            "HIBOSS_DEMO_NOTIFICATION_OPEN": "c1",
            "HIBOSS_DEMO_HISTORY_DELAY_MS": "10000",
            "HIBOSS_DEMO_MESSAGE_DELAY_MS": "10000",
        ])
        app.launchConfiguredDemo()

        XCTAssertFalse(app.staticTexts["message-question"].waitForExistence(timeout: 2))
        XCTAssertTrue(
            app.staticTexts["message-question"].waitForExistence(timeout: 15),
            "even a complete snapshot must wait for the current message API"
        )
        XCTAssertEqual(app.staticTexts["message-question"].label,
            "Production deploy will DROP 3 history tables (orders_2023 +2), irreversible. Run migration?")
        keepVerifiedScreenshot(app, name: "verified-notification-snapshot")
    }

    private func keepVerifiedScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
