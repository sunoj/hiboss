// Captures held intermediate states with the same demo launch path as functional UI tests.
// Exports IntermediateStateUITests; attachments cover language, appearance and Dynamic Type.
// Dependencies: XCTest, DemoLaunchSupport and deterministic demo delays.

import XCTest

final class IntermediateStateUITests: IntermediateCaptureCase {
    func testHomeCoverage() {
        for source in ["REQUESTS", "REQUESTS_READY", "PANELS", "QUESTIONNAIRES", "HISTORY"] {
            launch(["HIBOSS_DEMO_EMPTY": "1", "HIBOSS_DEMO_\(source)_DELAY_MS": "60000"])
            holdAndCapture("home-\(source.lowercased())")
        }
    }

    func testHomePartialAndConnection() {
        launch(["HIBOSS_DEMO_QUESTIONNAIRES_DELAY_MS": "60000"])
        holdAndCapture("home-partial")
        for state in ["connecting", "failed", "disconnected"] {
            launch(["HIBOSS_DEMO_EMPTY": "1", "HIBOSS_DEMO_CONNECTION": state])
            holdAndCapture("home-\(state)")
        }
        for state in ["silent", "ends"] {
            launch(["HIBOSS_DEMO_EMPTY": "1", "HIBOSS_DEMO_REQUESTS_STREAM": state])
            holdAndCapture("home-stream-\(state)")
        }
    }

    func testListConsumers() {
        launch(["HIBOSS_DEMO_HISTORY_DELAY_MS": "60000"])
        app.tabBars.buttons.element(boundBy: 1).tap()
        holdAndCapture("sessions-load")
        selectMessages()
        holdAndCapture("messages-load")
        launch(["HIBOSS_TAB": "progress", "HIBOSS_DEMO_PROGRESS_DELAY_MS": "60000"])
        holdAndCapture("progress-load")
    }

    func testDetailAndTranscript() {
        launch(["HIBOSS_DEMO_OPEN": "detail-old", "HIBOSS_DEMO_HISTORY_DELAY_MS": "60000",
                "HIBOSS_DEMO_MESSAGE_DELAY_MS": "60000"])
        holdAndCapture("detail-load")
        launch(["HIBOSS_DEMO_OPEN": "missing-message"])
        pause(2)
        capture("detail-missing")
        launch(["HIBOSS_DEMO_SESSION": "1", "HIBOSS_DEMO_TRANSCRIPT_DELAY_MS": "60000"])
        holdAndCapture("transcript-load")
        launch(["HIBOSS_DEMO_SESSION": "1",
                "HIBOSS_DEMO_TRANSCRIPT_CONNECTION_DELAY_MS": "60000"])
        holdAndCapture("transcript-reconnect")
    }

    func testResolvedAndTypedReply() {
        launch(["HIBOSS_DEMO_RESOLVED": "1", "HIBOSS_DEMO_HISTORY_DELAY_MS": "60000"])
        holdAndCapture("resolved-load")
        launch(["HIBOSS_DEMO_TEXT_ASK": "1", "HIBOSS_DEMO_OPEN": "demo-text-ask",
                "HIBOSS_DEMO_REPLY_DELAY_MS": "60000"])
        let field = app.textFields["message-reply-draft"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        field.typeText("Use the latest export")
        app.buttons[variant.contains("zh") ? "发送" : "Send"].firstMatch.tap()
        holdAndCapture("typed-reply")
    }

    func testReplies() {
        launch(["HIBOSS_DEMO_REPLY_DELAY_MS": "60000"])
        let choice = app.buttons["Reject"].firstMatch
        reveal(choice)
        choice.tap()
        holdAndCapture("home-reply")
        launch(["HIBOSS_DEMO_OPEN": "c1", "HIBOSS_DEMO_REPLY_DELAY_MS": "60000"])
        XCTAssertTrue(app.buttons["Reject"].firstMatch.waitForExistence(timeout: 8))
        app.buttons["Reject"].firstMatch.tap()
        holdAndCapture("detail-reply")
        launch(["HIBOSS_DEMO_SESSION": "1", "HIBOSS_DEMO_REPLY_DELAY_MS": "60000"])
        let transcriptChoice = app.buttons["Reject"].firstMatch
        for _ in 0..<5 where !transcriptChoice.isHittable { app.swipeDown() }
        XCTAssertTrue(transcriptChoice.waitForExistence(timeout: 8))
        transcriptChoice.tap()
        holdAndCapture("transcript-reply")
    }

    func testStaleConsumers() {
        launch(["HIBOSS_DEMO_REFRESH_FAILS": "1"])
        app.tabBars.buttons.element(boundBy: 1).tap()
        pause(6)
        pullToRefresh(app)
        pause(2)
        capture("sessions-stale")
        selectMessages()
        capture("messages-stale")
        app.tabBars.buttons.element(boundBy: 2).tap()
        pause(2)
        capture("progress-failed")
    }

}
