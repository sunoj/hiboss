// End-to-end coverage for opening a message from a notification-style deep link.
// Exports: NotificationDeepLinkUITests, proving push snapshots bypass all API waits.
// Dependencies: XCTest and the app's demo launch environment.

import XCTest

final class NotificationDeepLinkUITests: XCTestCase {
    func testNotificationSnapshotOpensWhileMessageAPIsAreStillLoading() {
        let app = XCUIApplication()
        app.configureDemoLaunch([
            "HIBOSS_DEMO_NOTIFICATION_OPEN": "c1",
            "HIBOSS_DEMO_HISTORY_DELAY_MS": "10000",
            "HIBOSS_DEMO_MESSAGE_DELAY_MS": "10000",
        ])
        app.launch()

        XCTAssertTrue(
            app.staticTexts["Production deploy will DROP 3 history tables (orders_2023 +2), irreversible. Run migration?"]
                .waitForExistence(timeout: 3),
            "a notification snapshot should render without waiting for any message API"
        )
    }
}
