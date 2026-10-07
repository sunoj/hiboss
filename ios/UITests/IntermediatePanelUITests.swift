// Held panel discovery, questionnaire loading/submission, preferences and web display evidence.
// Exports IntermediatePanelUITests; exercises native server-shaped demo questionnaires.
// Dependencies: IntermediateCaptureCase, DemoNativePanelAPI and shared panel UI.

import XCTest

final class IntermediatePanelUITests: IntermediateCaptureCase {
    func testQuestionsAndSubmission() {
        launchPanel(["HIBOSS_DEMO_QUESTIONS_DELAY_MS": "60000"])
        holdAndCapture("panel-questions")
        launchPanel(["HIBOSS_DEMO_SUBMISSION_DELAY_MS": "60000"])
        let submit = app.buttons["Submit checklist"].firstMatch
        XCTAssertTrue(submit.waitForExistence(timeout: 8))
        for _ in 0..<8 where !submit.isHittable { app.swipeUp() }
        submit.tap()
        holdAndCapture("questionnaire-submit")
    }

    func testPanelActionsAndRoute() {
        launchPanel(["HIBOSS_DEMO_PREFERENCE_DELAY_MS": "60000"])
        let actions = app.buttons[variant.contains("zh") ? "面板操作" : "Panel actions"].firstMatch
        XCTAssertTrue(actions.waitForExistence(timeout: 8))
        for _ in 0..<8 where !actions.isHittable { app.swipeUp() }
        actions.tap()
        app.buttons[variant.contains("zh") ? "置顶" : "Pin"].firstMatch.tap()
        holdAndCapture("panel-preference")
        launch(["HIBOSS_DEMO_NATIVE_PANEL": "1", "HIBOSS_DEMO_PANEL_OPEN": "demo-panel",
                "HIBOSS_DEMO_PANELS_DELAY_MS": "60000"])
        holdAndCapture("panel-route")
    }

    func testSavedAnswerRecovery() {
        launchPanel(["HIBOSS_DEMO_RECOVERY_DELAY_MS": "60000"])
        let checking = app.buttons[variant.contains("zh") ? "正在核对已保存的回答…" : "Checking saved answer…"]
            .firstMatch
        XCTAssertTrue(checking.waitForExistence(timeout: 8))
        for _ in 0..<8 where !checking.isHittable { app.swipeUp() }
        holdAndCapture("questionnaire-recovery")
    }

    func testPanelStreamStates() {
        for state in ["awaiting", "stale", "offline"] {
            launchPanel(["HIBOSS_DEMO_PANEL_FRESHNESS": state])
            holdAndCapture("panel-stream-" + state)
        }
    }

    func testWebDisplay() {
        launch(["HIBOSS_PANELS_DEMO": "1", "HIBOSS_DEMO_PANEL_OPEN": "benchmark-sweep.json",
                "HIBOSS_DEMO_WEB_DELAY_MS": "60000"])
        holdAndCapture("panel-web")
        let done = app.buttons[variant.contains("zh") ? "完成" : "Done"].firstMatch
        XCTAssertTrue(done.exists)
        XCTAssertTrue(done.isHittable, "A pending display must leave the panel's close control reachable")
    }

    private func launchPanel(_ extra: [String: String]) {
        var environment = ["HIBOSS_DEMO_NATIVE_PANEL": "1", "HIBOSS_DEMO_PANEL_OPEN": "demo-panel"]
        environment.merge(extra) { _, new in new }
        launch(environment)
        XCTAssertTrue(app.navigationBars["Release checklist"].waitForExistence(timeout: 10))
    }
}
