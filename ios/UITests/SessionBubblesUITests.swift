// UI coverage for session bubbles, collapsed step runs, and decisions answered in the transcript.
// Exports: SessionBubblesUITests.
// Dependencies: XCTest, DemoLaunchSupport.

import XCTest

final class SessionBubblesUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.configureDemoLaunch(["HIBOSS_DEMO_SESSION": "1"])
        app.launchConfiguredDemo()
    }

    func testSessionDetailShowsBubblesAndSystemLines() {
        XCTAssertTrue(
            app.navigationBars["prod-release"].waitForExistence(timeout: 10),
            "demo session route should open the prod-release transcript"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["session-bubble-incoming"].waitForExistence(timeout: 8),
            "agent messages must render as incoming bubbles"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["session-bubble-outgoing"].exists,
            "boss messages must render as outgoing bubbles"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["session-system-line"].exists,
            "tool calls, results and hooks stay collapsed until the boss asks"
        )
        XCTAssertFalse(app.staticTexts["future_kind · kept by fallback"].exists, "unknown kinds are never shown raw")
        let steps = app.buttons["session-steps"].firstMatch
        XCTAssertTrue(steps.waitForExistence(timeout: 5), "activity collapses into one steps row")
        XCTAssertTrue(steps.label.contains("3 steps"), "known activity is counted, got \(steps.label)")
        steps.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["session-system-line"].waitForExistence(timeout: 5),
            "expanding the run shows each step's detail"
        )
        XCTAssertTrue(app.buttons["Show more"].exists, "long tool output must offer expand")
    }

    func testPendingDecisionIsAnsweredInPlace() {
        let card = app.descendants(matching: .any)["transcript-decision-c1"]
        XCTAssertTrue(card.waitForExistence(timeout: 10), "the pending migration decision renders as a decision card")
        XCTAssertTrue(app.descendants(matching: .any)["decision-timing-c1"].exists, "same timing line as Home")
        let approve = card.buttons["Approve"]
        XCTAssertTrue(approve.waitForExistence(timeout: 5), "options are answerable from the transcript")
        approve.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["transcript-answer-c1"].waitForExistence(timeout: 8),
            "the answered decision shows its answer in place"
        )
        XCTAssertFalse(card.buttons["Approve"].exists, "options leave once answered")
        XCTAssertTrue(
            app.descendants(matching: .any)["transcript-answer-c0"].exists,
            "an earlier decision shows the recorded answer"
        )
    }

    func testPendingDecisionUsesOneCardWithOptionsBeforeDefaultAndOnlyTheSessionComposer() {
        let card = app.descendants(matching: .any)["transcript-decision-c1"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertEqual(card.textFields.count, 0, "the bottom session composer owns text replies")
        XCTAssertEqual(card.textViews.count, 0)
        let question = card.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Run migration?'"))
        XCTAssertEqual(question.count, 1, "the card contains the question once")
        let changes = card.staticTexts["The migration cannot be undone once it starts."]
        let approve = card.buttons["Approve"]
        let timing = card.descendants(matching: .any)["decision-timing-c1"]
        XCTAssertTrue(changes.exists)
        XCTAssertLessThan(question.firstMatch.frame.maxY, changes.frame.minY)
        XCTAssertLessThan(changes.frame.maxY, approve.frame.minY)
        XCTAssertLessThanOrEqual(approve.frame.maxY, timing.frame.minY)
        XCTAssertEqual(card.descendants(matching: .any)
            .matching(identifier: "session-bubble-incoming").count, 0)
        XCTAssertTrue(app.textFields["session-reply-draft"].isHittable)
    }
    func testLightReplyTargets() { captureReplyTargets("Light") }
    func testDarkReplyTargets() { captureReplyTargets("Dark") }

    private func captureReplyTargets(_ appearance: String) {
        app.terminate()
        app.configureDemoLaunch(["HIBOSS_DEMO_SESSION": "1"])
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-AppleInterfaceStyle", appearance]
        app.launchConfiguredDemo()
        let label = app.staticTexts["session-reply-target"]
        XCTAssertTrue(label.waitForExistence(timeout: 10))
        XCTAssertEqual(label.label, "Custom answer to: Production deploy will DROP 3 history tables "
                       + "(orders_2023 +2), irreversible. Run migration?")
        keepReplyScreenshot("en-\(appearance.lowercased())-custom-answer")
        app.terminate()
        app.configureDemoLaunch(["HIBOSS_DEMO_SESSION": "1", "HIBOSS_DEMO_EMPTY": "1"])
        app.launchConfiguredDemo()
        XCTAssertTrue(label.waitForExistence(timeout: 10))
        XCTAssertEqual(label.label, "Replying to: Deployment to staging complete. All 214 tests green.")
        keepReplyScreenshot("en-\(appearance.lowercased())-ordinary-reply")
    }

    func testResolvedThreadCardHasNoDefaultLine() {
        let card = app.descendants(matching: .any)["transcript-decision-c1"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.buttons["Approve"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["transcript-answer-c1"]
            .waitForExistence(timeout: 10))
        XCTAssertFalse(card.descendants(matching: .any)["decision-timing-c1"].exists)
    }

    func testNoDeadlineAppearsOnceOnTodayAndDetail() {
        app.terminate()
        app.configureDemoLaunch()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchConfiguredDemo()
        let card = app.buttons["home-message-c3"]
        for _ in 0..<8 where !card.isHittable { app.swipeUp() }
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertEqual(card.label.components(separatedBy: "No deadline").count - 1, 1)
        let timing = app.descendants(matching: .any)["decision-timing-c3"]
        XCTAssertFalse(timing.label.contains("No deadline"), "the header already states the deadline")
        card.tap()
        XCTAssertTrue(app.staticTexts["message-question"].waitForExistence(timeout: 5))
        XCTAssertEqual(timing.label.components(separatedBy: "No deadline").count - 1, 1)
    }

    func testResolvedDetailHasNoDefaultLine() {
        app.terminate()
        app.configureDemoLaunch(["HIBOSS_DEMO_OPEN": "a1"])
        app.launchConfiguredDemo()
        XCTAssertTrue(app.staticTexts["message-question"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["decision-timing-a1"].exists)
    }

    func testNewMessageKeepsDraftTargetUntilBossSwitches() {
        app.terminate()
        app.configureDemoLaunch(["HIBOSS_DEMO_SESSION": "1",
                                 "HIBOSS_DEMO_TRANSCRIPT_NEWER_DELAY_MS": "15000"])
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchConfiguredDemo()
        let label = app.staticTexts["session-reply-target"]
        XCTAssertTrue(label.waitForExistence(timeout: 10))
        let original = label.label
        XCTAssertTrue(original.hasPrefix("Custom answer to:"))
        let field = app.textFields["session-reply-draft"]
        field.tap()
        field.typeText("Keep this draft")
        let switchTarget = app.buttons["Reply to the newer message"]
        XCTAssertTrue(switchTarget.waitForExistence(timeout: 20))
        XCTAssertEqual(label.label, original)
        XCTAssertEqual(field.value as? String, "Keep this draft")
        switchTarget.tap()
        XCTAssertEqual(label.label, "Replying to: A newer release update.")
        XCTAssertEqual(field.value as? String, "Keep this draft")
        app.buttons["Send reply"].tap()
        XCTAssertTrue(app.staticTexts["reply-confirmation"].waitForExistence(timeout: 10))
        XCTAssertFalse(field.value as? String == "Keep this draft")
        XCTAssertTrue(app.descendants(matching: .any)["transcript-decision-c1"].buttons["Approve"].exists,
                      "sending to the newer ordinary message must not answer the original decision")
    }

    func testReplyLabelsAreLocalizedInChinese() {
        app.terminate()
        app.configureDemoLaunch(["HIBOSS_DEMO_SESSION": "1"])
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchConfiguredDemo()
        let label = app.staticTexts["session-reply-target"]
        XCTAssertTrue(label.waitForExistence(timeout: 10))
        XCTAssertTrue(label.label.hasPrefix("自定义回答："))
        app.terminate()
        app.configureDemoLaunch(["HIBOSS_DEMO_SESSION": "1", "HIBOSS_DEMO_EMPTY": "1"])
        app.launchConfiguredDemo()
        XCTAssertTrue(label.waitForExistence(timeout: 10))
        XCTAssertTrue(label.label.hasPrefix("回复对象："))
    }

    private func keepReplyScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

}
