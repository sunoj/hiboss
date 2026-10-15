// Exercises session thread relationships, inline answers, reaction chips and appearance captures.
// Dependencies: XCTest and configured demo launches on the task's simulator.

import XCTest

final class SessionThreadsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testLightThreadsAndReactions() { captureConversation("Light") }
    func testDarkThreadsAndReactions() { captureConversation("Dark") }
    func testLargeTextThreadsAndReactions() { captureConversation("Light", largeText: true) }

    func testAnswerLeavesNeedsYouAndAppearsInConversation() {
        let app = launch("Light", empty: false)
        let decision = app.descendants(matching: .any)["transcript-decision-c5"]
        XCTAssertTrue(decision.waitForExistence(timeout: 10))
        XCTAssertTrue(decision.buttons["Coarse grid"].isHittable)
        let pinned = app.descendants(matching: .any)["needs-thread-c5"]
        XCTAssertTrue(pinned.staticTexts["I can keep the previous batch ready while you decide."].exists)
        keep(app, "needs-you-light")
        decision.buttons["Coarse grid"].tap()
        let answer = app.descendants(matching: .any)["transcript-answer-c5"]
        for _ in 0..<8 where !answer.isHittable { app.swipeUp() }
        XCTAssertTrue(answer.waitForExistence(timeout: 10))
        XCTAssertFalse(decision.buttons["Coarse grid"].exists)
        XCTAssertTrue(app.textFields["session-reply-draft"].isEnabled)
        keep(app, "answered-light")
    }

    func testReactionChipsAppearOnMessageDetail() {
        let app = XCUIApplication()
        app.configureDemoLaunch(["HIBOSS_DEMO_THREADS": "1", "HIBOSS_DEMO_OPEN": "thread-followup"])
        app.launchConfiguredDemo()
        let reaction = app.staticTexts["reaction-thread-followup-👍"]
        XCTAssertTrue(reaction.waitForExistence(timeout: 10))
        XCTAssertEqual(reaction.label, "👍, 2 reactions")
        keep(app, "detail-reactions")
    }

    func testCachedSessionRefreshKeepsThreadAndChoiceFrames() {
        let app = XCUIApplication()
        app.configureDemoLaunch(["HIBOSS_DEMO_SESSION": "1",
                                 "HIBOSS_DEMO_TRANSCRIPT_RESYNC_DELAY_MS": "15000",
                                 "HIBOSS_DEMO_TRANSCRIPT_REFRESH_DELAY_MS": "10000"])
        app.launchConfiguredDemo()
        let choice = app.buttons["Coarse grid"]
        XCTAssertTrue(choice.waitForExistence(timeout: 10))
        pullToRefresh(app)
        let frame = choice.frame
        let notice = app.alerts["Transcript reloaded"]
        XCTAssertTrue(notice.waitForExistence(timeout: 25), "the stream must request a reload")
        notice.buttons["OK"].tap()
        let refreshing = app.staticTexts["list-stale-banner"]
        XCTAssertTrue(refreshing.waitForExistence(timeout: 5), "the reload must fetch cached content")
        XCTAssertTrue(choice.isEnabled)
        XCTAssertEqual(choice.frame, frame)
        XCTAssertFalse(app.descendants(matching: .any)["pending-rows"].exists)
        keep(app, "session-mid-refresh")
        XCTAssertTrue(refreshing.waitForNonExistence(timeout: 15))
        XCTAssertEqual(choice.frame, frame)
    }

    func testNewMessageFollowsLiveAndJumpRestoresFollowing() {
        let app = XCUIApplication()
        app.configureDemoLaunch(["HIBOSS_DEMO_SESSION": "1", "HIBOSS_DEMO_EMPTY": "1",
                                 "HIBOSS_DEMO_THREADS": "1",
                                 "HIBOSS_DEMO_TRANSCRIPT_NEWER_DELAY_MS": "15000"])
        app.launchConfiguredDemo()
        XCTAssertTrue(app.staticTexts["Release notes are ready."].waitForExistence(timeout: 10))
        app.swipeUp()
        let incoming = app.staticTexts["A newer release update.\nMore context follows."]
        XCTAssertTrue(incoming.waitForExistence(timeout: 25))
        XCTAssertTrue(incoming.isHittable, "a new message stays visible while following live")
        app.swipeDown()
        let jump = app.buttons["jump-to-live"]
        XCTAssertTrue(jump.waitForExistence(timeout: 5))
        jump.tap()
        XCTAssertTrue(jump.waitForNonExistence(timeout: 5))
        XCTAssertTrue(incoming.isHittable)
    }

    private func captureConversation(_ appearance: String, largeText: Bool = false) {
        let pending = launch(appearance, largeText: largeText, empty: false)
        XCTAssertTrue(pending.staticTexts["Needs you"].waitForExistence(timeout: 10))
        keep(pending, "\(appearance)-needs-you")
        pending.terminate()
        let app = launch(appearance, largeText: largeText)
        let root = app.descendants(matching: .any)["transcript-decision-thread-question"]
        XCTAssertTrue(root.waitForExistence(timeout: 10))
        XCTAssertTrue(root.staticTexts["Use the smaller release batch?"].exists)
        XCTAssertTrue(root.descendants(matching: .any)["transcript-answer-thread-question"].exists)
        let followup = root.descendants(matching: .any)["followup-thread-followup"]
        XCTAssertTrue(followup.exists)
        XCTAssertFalse(followup.staticTexts["orchestrator-01"].exists)
        let reaction = app.staticTexts["reaction-thread-followup-👍"]
        for _ in 0..<4 where !reaction.isHittable { app.swipeUp() }
        XCTAssertTrue(reaction.isHittable)
        XCTAssertEqual(reaction.label, "👍, 2 reactions")
        keep(app, "\(appearance)-\(largeText ? "large" : "standard")-conversation")
        let merged = app.descendants(matching: .any)["thread-update-first"]
        for _ in 0..<6 where !merged.isHittable { app.swipeUp() }
        XCTAssertTrue(merged.staticTexts["Release notes are ready."].exists)
        XCTAssertTrue(merged.staticTexts["The staging checks are green too."].exists)
        XCTAssertEqual(merged.staticTexts.matching(identifier: "orchestrator-01").count, 1)
        XCTAssertFalse(merged.buttons["Details"].exists)
        keep(app, "\(appearance)-\(largeText ? "large" : "standard")-merged")
    }

    private func launch(_ appearance: String, largeText: Bool = false,
                        empty: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.configureDemoLaunch(["HIBOSS_DEMO_SESSION": "1", "HIBOSS_DEMO_THREADS": "1",
                                 "HIBOSS_DEMO_EMPTY": empty ? "1" : "0"])
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-AppleInterfaceStyle", appearance]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName",
                                    "UICTContentSizeCategoryAccessibilityL"]
        }
        app.launchConfiguredDemo()
        return app
    }

    private func keep(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "threads-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
