// End-to-end coverage for opening a message from a notification-style deep link.
// Exports: NotificationDeepLinkUITests: detail loading precedes the API response, and a tap
// arriving over an open full-screen viewer closes it so the message is what shows.
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
            app.staticTexts["message-question"].appears(timeout: 15),
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
            app.staticTexts["message-question"].appears(timeout: 15),
            "the detail fetch must render without waiting for history or required inputs"
        )
        XCTAssertEqual(app.staticTexts["message-question"].label,
            "Production deploy will DROP 3 history tables (orders_2023 +2), irreversible. Run migration?")
        XCTAssertFalse(app.staticTexts["Loading message…"].exists)
        keepVerifiedScreenshot(app, name: "notification-from-progress-content")
    }

    func testNotificationOverProgressMediaViewerClosesItAndShowsTheMessage() {
        assertNotificationClosesViewer(["HIBOSS_TAB": "progress"], message: "c1", tab: 3, name: "progress") {
            $0.images["wide landscape screenshot"].firstMatch
        }
    }

    func testNotificationOverTodayMarkdownImageClosesItAndShowsTheMessage() {
        assertNotificationClosesViewer(
            ["HIBOSS_DEMO_OPTION_MEDIA": "pending", "HIBOSS_DEMO_MARKDOWN_IMAGES": "1"],
            message: "media-decision", tab: 0, name: "today"
        ) { $0.buttons["markdown-media-open"].firstMatch }
    }

    /// Opens a full-screen viewer from a tab, lets a delayed notification tap arrive over it,
    /// then checks the message shows and the closed viewer can open again.
    private func assertNotificationClosesViewer(
        _ route: [String: String], message: String, tab: Int, name: String,
        opener: (XCUIApplication) -> XCUIElement
    ) {
        let app = XCUIApplication()
        app.configureDemoLaunch(route.merging([
            "HIBOSS_DEMO_NOTIFICATION_OPEN": message, "HIBOSS_DEMO_NOTIFICATION_DELAY_MS": "10000",
        ]) { $1 })
        app.launchConfiguredDemo()
        let media = opener(app)
        XCTAssertTrue(media.appears(timeout: 8), "the demo media should appear")
        media.tap()
        let close = app.buttons["media-viewer-close"]
        XCTAssertTrue(close.appears(timeout: 5), "the viewer must be open before the tap arrives")
        keepVerifiedScreenshot(app, name: "notification-over-\(name)-viewer-before")

        XCTAssertTrue(close.disappears(timeout: 15), "the notification must close the viewer")
        XCTAssertTrue(app.staticTexts["message-question"].appears(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons.element(boundBy: 1).isSelected)
        keepVerifiedScreenshot(app, name: "notification-over-\(name)-viewer-after")

        app.tabBars.buttons.element(boundBy: tab).tap()
        XCTAssertTrue(media.appears(timeout: 5))
        media.tap()
        XCTAssertTrue(close.appears(timeout: 5), "a closed viewer must open again")
    }

    private func assertDetailLoading(_ app: XCUIApplication, name: String) {
        XCTAssertTrue(app.navigationBars["Loading…"].appears(timeout: 2),
            "notification navigation must precede the held message fetch")
        XCTAssertTrue(app.staticTexts["Loading message…"].appears(timeout: 2))
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
