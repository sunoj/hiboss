// Behavioral assertions for slow coverage, safe reply admission and retained typed input.
// Exports IntermediateBehaviorUITests alongside before/after state attachments.
// Dependencies: IntermediateCaptureCase, demo API failures and native accessibility controls.

import XCTest

final class IntermediateBehaviorUITests: IntermediateCaptureCase {
    func testMissingReadyEscalatesAndSettingsIsReachable() {
        launch(["HIBOSS_DEMO_EMPTY": "1", "HIBOSS_DEMO_REQUESTS_STREAM": "silent"])
        let retry = app.buttons["pending-retry"].firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 12))
        XCTAssertFalse(app.staticTexts["Nothing needs you"].exists)
        let status = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Requests connection'"))
            .firstMatch
        if !variant.contains("zh") { XCTAssertTrue(status.exists) }
        capture("missing-ready-action")
        app.buttons[variant.contains("zh") ? "设置" : "Settings"].firstMatch.tap()
        XCTAssertTrue(
            app.navigationBars[variant.contains("zh") ? "设置" : "Settings"].waitForExistence(timeout: 5))
    }

    func testReplyOnlyDisablesItsOwnDecision() {
        launch(["HIBOSS_DEMO_REPLY_DELAY_MS": "60000"])
        let reject = app.buttons["Reject"].firstMatch
        XCTAssertTrue(reject.waitForExistence(timeout: 8))
        reject.tap()
        XCTAssertFalse(reject.isEnabled)
        XCTAssertFalse(app.buttons["Approve"].firstMatch.isEnabled)
        XCTAssertTrue(app.buttons["Fine grid"].firstMatch.isEnabled)
        XCTAssertTrue(app.buttons["home-message-c1"].isEnabled)
    }

    func testTypedReplyKeepsDraftAfterFailure() {
        launch(["HIBOSS_DEMO_TEXT_ASK": "1", "HIBOSS_DEMO_OPEN": "demo-text-ask",
                "HIBOSS_DEMO_REPLY_DELAY_MS": "2000", "HIBOSS_DEMO_REPLY_FAILS": "1"])
        let draft = app.textFields["message-reply-draft"].firstMatch
        XCTAssertTrue(draft.waitForExistence(timeout: 8))
        draft.tap()
        draft.typeText("Use the latest export")
        let send = app.buttons[variant.contains("zh") ? "发送" : "Send"].firstMatch
        send.tap()
        XCTAssertTrue(draft.isEnabled)
        XCTAssertFalse(send.isEnabled)
        pause(3)
        XCTAssertEqual(draft.value as? String, "Use the latest export")
        XCTAssertTrue(send.isEnabled)
        capture("typed-reply-failed")
    }

    func testRefreshKeepsHomeAndListContent() {
        launch(["HIBOSS_DEMO_REFRESH_DELAY_MS": "60000"])
        XCTAssertTrue(app.buttons["home-message-c1"].waitForExistence(timeout: 8))
        pause(6)
        pullToRefresh(app)
        XCTAssertTrue(app.buttons["home-message-c1"].exists)
        holdAndCapture("home-refresh")
        app.tabBars.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.cells.firstMatch.exists)
        holdAndCapture("sessions-refresh")
        launch(["HIBOSS_DEMO_REFRESH_FAILS": "1"])
        pause(6)
        pullToRefresh(app)
        pause(2)
        capture("home-stale")
    }

    func testImageRetryRestartsProgressAndKeepsZoomReachable() {
        launch(["HIBOSS_DEMO_OPTION_MEDIA": "pending", "HIBOSS_DEMO_MEDIA_DELAY_MS": "60000"])
        let retry = app.buttons["option-media-retry-Coastal view"].firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 12))
        retry.tap()
        XCTAssertTrue(retry.waitForNonExistence(timeout: 2))
        let zoom = app.buttons["Open image for Coastal view"].firstMatch
        XCTAssertTrue(zoom.isEnabled)
        zoom.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.1)).tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3))
    }
}
