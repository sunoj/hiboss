// Cached refresh and recovery checks using real native screens on the assigned simulator.
// Exports StableSurfaceUITests and paired Chinese light-mode screenshot attachments.
// Dependencies: IntermediateCaptureCase and controlled demo service latency.

import XCTest

final class StableSurfaceUITests: IntermediateCaptureCase {
    override var variant: String { "zh" }
    override var appearance: String? { "Light" }

    func testMissingMessageRetryRetainsTheCompletedResult() {
        launch(["HIBOSS_DEMO_OPEN": "missing-message", "HIBOSS_DEMO_MESSAGE_DELAY_MS": "2500"])
        let retry = app.buttons["pending-retry"].firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 8))
        capture("detail-missing-settled")
        let frame = retry.frame
        retry.tap()
        pause(0.5)
        capture("detail-missing-mid-refresh")
        XCTAssertTrue(retry.exists, "Retry must retain the completed not-found result")
        XCTAssertEqual(retry.frame, frame)
    }

    func testMarkdownErrorRetryRetainsTheCompletedResult() {
        launch(["HIBOSS_DEMO_OPEN": "attachment-file", "HIBOSS_DEMO_ATTACHMENTS": "markdown-error",
                "HIBOSS_DEMO_MEDIA_DELAY_MS": "2000"])
        let preview = app.buttons["message-attachment-markdown-preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        preview.tap()
        let retry = app.buttons["重试"].firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 8))
        capture("markdown-settled")
        retry.tap()
        pause(0.5)
        capture("markdown-mid-refresh")
        XCTAssertTrue(retry.exists, "An error retry must keep the result while the read runs")
    }

    func testAllClearSurvivesHeldRefreshAndItsWatchdog() {
        launch(["HIBOSS_DEMO_EMPTY": "1", "HIBOSS_DEMO_REFRESH_DELAY_MS": "60000"])
        let clear = app.descendants(matching: .any)["today-all-clear"].firstMatch
        XCTAssertTrue(clear.waitForExistence(timeout: 10))
        pause(6)
        capture("home-empty-settled")
        pullToRefresh(app)
        pause(9)
        capture("home-empty-mid-refresh")
        XCTAssertTrue(clear.exists)
        XCTAssertFalse(app.descendants(matching: .any)["pending-rows"].exists)
    }

    func testHomeChoicesKeepTheirFramesDuringRefresh() {
        launch(["HIBOSS_DEMO_REFRESH_DELAY_MS": "60000"])
        let choice = app.buttons["Reject"].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 10))
        pause(6)
        let frame = choice.frame
        capture("home-settled")
        pullToRefresh(app)
        pause(9)
        capture("home-mid-refresh")
        XCTAssertTrue(choice.exists)
        XCTAssertTrue(choice.isEnabled)
        XCTAssertEqual(choice.frame, frame)
    }

    func testActivityAndMessagesKeepTheirViewport() {
        launch(["HIBOSS_DEMO_REFRESH_DELAY_MS": "4000"])
        app.tabBars.buttons.element(boundBy: 1).tap()
        pause(6)
        capture("sessions-settled")
        pullToRefresh(app)
        pause(0.5)
        capture("sessions-mid-refresh")
        XCTAssertTrue(app.cells.firstMatch.exists)
        pause(4)
        selectMessages()
        capture("messages-settled")
        pullToRefresh(app)
        pause(0.5)
        capture("messages-mid-refresh")
        XCTAssertTrue(app.cells.firstMatch.exists)
    }

    func testDetailKeepsItsReplyFieldAcrossForegroundRefresh() {
        launch(["HIBOSS_DEMO_OPEN": "c1", "HIBOSS_DEMO_REFRESH_DELAY_MS": "60000"])
        let field = app.textFields["message-reply-draft"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        reveal(field)
        pause(6)
        capture("detail-settled")
        XCUIDevice.shared.press(.home)
        app.activate()
        pause(9)
        capture("detail-mid-refresh")
        XCTAssertTrue(field.exists)
        XCTAssertTrue(field.isEnabled)
    }

    func testTranscriptKeepsItsComposerAcrossForegroundRefresh() {
        launch(["HIBOSS_DEMO_SESSION": "1", "HIBOSS_DEMO_REFRESH_DELAY_MS": "60000"])
        let field = app.textFields["session-reply-draft"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        pause(6)
        capture("transcript-settled")
        XCUIDevice.shared.press(.home)
        app.activate()
        pause(9)
        capture("transcript-mid-refresh")
        XCTAssertTrue(field.exists)
        XCTAssertTrue(field.isEnabled)
        XCTAssertFalse(app.buttons["Discard draft"].exists)
    }

    func testEmptyPanelFilterKeepsRefreshEnabledDuringRead() {
        launch(["HIBOSS_DEMO_NATIVE_PANEL": "1", "HIBOSS_DEMO_REQUESTS_EMPTY": "1",
                "HIBOSS_DEMO_REFRESH_DELAY_MS": "4000"])
        let picker = app.descendants(matching: .any)["panel-wall-filter"].firstMatch
        reveal(picker)
        if app.segmentedControls["panel-wall-filter"].exists {
            app.segmentedControls["panel-wall-filter"].buttons.element(boundBy: 1).tap()
        } else {
            picker.tap()
            app.buttons.matching(NSPredicate(format: "label CONTAINS '需要输入'" )).firstMatch.tap()
        }
        let refresh = app.buttons["panel-wall-refresh"].firstMatch
        reveal(refresh)
        pause(6)
        capture("panel-filter-settled")
        refresh.tap()
        pause(0.5)
        capture("panel-filter-mid-refresh")
        XCTAssertTrue(refresh.exists)
        XCTAssertTrue(refresh.isEnabled)
    }

    func testPanelPollingKeepsTheQuestionnaireFieldInPlace() {
        launch(["HIBOSS_DEMO_NATIVE_PANEL": "1", "HIBOSS_DEMO_PANEL_OPEN": "demo-panel",
                "HIBOSS_DEMO_PANEL_FRESHNESS": "stale", "HIBOSS_DEMO_REFRESH_DELAY_MS": "8000"])
        XCTAssertTrue(app.navigationBars["Release checklist"].waitForExistence(timeout: 10))
        let submit = app.buttons["Submit checklist"].firstMatch
        reveal(submit)
        let frame = submit.frame
        capture("panel-detail-mid-refresh")
        pause(9)
        capture("panel-detail-settled")
        XCTAssertEqual(submit.frame, frame)
        XCTAssertTrue(submit.isEnabled)
    }

    func testDeviceInventoryKeepsRevocationEnabledDuringRead() {
        launch(["HIBOSS_DEMO_REFRESH_DELAY_MS": "4000"])
        app.buttons["today-settings"].tap()
        app.buttons["settings-devices"].tap()
        let refresh = app.buttons["boss-clients-refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 10))
        pause(6)
        capture("devices-settled")
        let revoke = app.buttons["boss-client-revoke-demo-mac"]
        let frame = revoke.frame
        refresh.tap()
        pause(0.5)
        capture("devices-mid-refresh")
        XCTAssertTrue(revoke.isEnabled)
        XCTAssertEqual(revoke.frame, frame)
    }

    func testDeviceRequestEmptyResultSurvivesFailedRefreshAndRetry() {
        launch(["HIBOSS_DEMO_REQUESTS_EMPTY": "1", "HIBOSS_DEMO_REFRESH_DELAY_MS": "4000",
                "HIBOSS_DEMO_REFRESH_FAILS": "1"])
        app.buttons["today-settings"].tap()
        app.buttons["settings-devices"].tap()
        app.buttons["设备请求"].firstMatch.tap()
        let empty = app.descendants(matching: .any)["device-requests-empty"].firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 10))
        pause(6)
        capture("device-requests-settled")
        pullToRefresh(app)
        pause(0.5)
        capture("device-requests-mid-refresh")
        XCTAssertTrue(empty.exists)
        let retry = app.buttons["pending-retry"].firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 8))
        retry.tap()
        pause(0.5)
        XCTAssertTrue(empty.exists)
    }

    func testProgressKeepsPostsDuringRefresh() {
        launch(["HIBOSS_TAB": "progress", "HIBOSS_DEMO_REFRESH_DELAY_MS": "4000"])
        pause(6)
        capture("progress-settled")
        pullToRefresh(app)
        pause(0.5)
        capture("progress-mid-refresh")
        XCTAssertTrue(app.cells.firstMatch.exists)
    }
}
