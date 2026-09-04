// End-to-end coverage for opening a message from a notification-style deep link.
// Exports: NotificationDeepLinkUITests, proving detail loading bypasses slow history.
// Dependencies: XCTest and the app's demo launch environment.

import XCTest

final class NotificationDeepLinkUITests: XCTestCase {
    func testNotificationMessageOpensWhileHistoryIsStillLoading() {
        let app = XCUIApplication()
        app.configureDemoLaunch([
            "HIBOSS_DEMO_OPEN": "c1",
            "HIBOSS_DEMO_HISTORY_DELAY_MS": "10000",
        ])
        app.launch()

        XCTAssertTrue(
            app.staticTexts["Production deploy will DROP 3 history tables (orders_2023 +2), irreversible. Run migration?"]
                .waitForExistence(timeout: 3),
            "a notification should fetch its target without waiting for full history"
        )
    }
}
