// Exercises phase B session search, replies, Box filters, and decision sheet navigation.
// Exports SessionsV4UITests with retained light/dark evidence of each changed screen.
// Dependencies: XCTest and launchConfiguredDemo with offline production service boundaries.

import XCTest

@MainActor
final class SessionsV4UITests: XCTestCase {
    private func launch(_ appearance: String = "Light", extra: [String: String] = [:],
                        arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.configureDemoLaunch(extra)
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-AppleInterfaceStyle", appearance] + arguments
        app.launchConfiguredDemo()
        return app
    }

    func testLightScreens() { capture("Light") }
    func testDarkScreens() { capture("Dark") }

    private func capture(_ appearance: String) {
        continueAfterFailure = false
        var app = launch(appearance)
        XCTAssertTrue(app.buttons["home-message-c5"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Sessions"].tap()
        XCTAssertTrue(app.buttons["activity-session-sess-deploy"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Needs you"].exists)
        shot(app, "\(appearance)-sessions")
        app.buttons["activity-session-sess-deploy"].tap()
        XCTAssertTrue(app.staticTexts["Mac mini"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Preparing the release"].exists)
        let open = app.descendants(matching: .any)["transcript-decision-c1"]
        for _ in 0..<8 where !open.buttons["Approve"].isHittable { app.swipeDown() }
        XCTAssertTrue(open.buttons["Approve"].isHittable)
        shot(app, "\(appearance)-thread-open")
        let resolved = app.descendants(matching: .any)["transcript-answer-c0"]
        for _ in 0..<8 where !resolved.isHittable { app.swipeDown() }
        XCTAssertTrue(resolved.isHittable)
        shot(app, "\(appearance)-thread-resolved")
        app.buttons["Message history"].tap()
        XCTAssertTrue(app.navigationBars["Messages"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Box"].tap()
        XCTAssertTrue(app.buttons["box-item-demo-agent-text"].waitForExistence(timeout: 10))
        shot(app, "\(appearance)-box")
        app.terminate()
        app = launch(appearance, extra: ["HIBOSS_DEMO_ATTACHMENTS": "1", "HIBOSS_DEMO_SESSION": "1"])
        XCTAssertTrue(app.images["message-attachment-image"].firstMatch.waitForExistence(timeout: 10))
        shot(app, "\(appearance)-thread-image")
        app.terminate()
        app = launch(appearance)
        let decision = app.buttons["home-message-c1"]
        XCTAssertTrue(decision.waitForExistence(timeout: 10))
        for _ in 0..<8 where !decision.isHittable { app.swipeUp() }
        decision.tap()
        XCTAssertTrue(app.staticTexts["decision-facts"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Reject"].waitForExistence(timeout: 5))
        shot(app, "\(appearance)-decision-detail")
        app.terminate()
    }

    func testSessionSearchFindsMessagesAndThreadHistoryRemainsReachable() {
        let app = launch()
        XCTAssertTrue(app.tabBars.buttons["Sessions"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Sessions"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("DROP")
        let result = app.buttons["session-search-message-c1"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertTrue(app.staticTexts["message-question"].waitForExistence(timeout: 5))
    }

    func testReplyCanAttachBoxReferenceAndSendInSession() {
        let app = launch(extra: ["HIBOSS_DEMO_SESSION": "1"])
        let field = app.textFields["session-reply-draft"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        app.buttons["Attach from Box"].tap()
        let item = app.buttons["box-item-demo-agent-text"]
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        item.tap()
        XCTAssertTrue((field.value as? String)?.contains("box:demo-agent-text") == true)
        app.buttons["Send reply"].tap()
        XCTAssertTrue(app.staticTexts["reply-confirmation"].waitForExistence(timeout: 10))
        XCTAssertFalse((field.value as? String)?.contains("box:demo-agent-text") == true)
        let outgoing = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == 'session-bubble-outgoing' AND label CONTAINS 'box:demo-agent-text'"
        )).firstMatch
        XCTAssertTrue(outgoing.waitForExistence(timeout: 10), "the receipt must appear in this thread")
    }

    func testBoxGridColumnsFitScreenWithoutOverlap() {
        let app = launch()
        XCTAssertTrue(app.tabBars.buttons["Box"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Box"].tap()
        let agent = app.buttons["box-item-demo-agent-text"]
        let image = app.buttons["box-item-demo-image"]
        XCTAssertTrue(image.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(agent.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(image.frame.maxX, app.frame.maxX)
        XCTAssertLessThanOrEqual(agent.frame.maxX, image.frame.minX)
        XCTAssertEqual(agent.frame.minY, image.frame.minY, accuracy: 2)
    }

    func testFastTranscriptLoadLeavesLoadingState() {
        let app = launch(extra: ["HIBOSS_DEMO_SESSION": "1"])
        XCTAssertTrue(app.buttons["Message history"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Refreshing. Showing earlier results."].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Approve"].exists)
    }

    func testThreadRemainsUsableAtAccessibilityTextSize() {
        let app = launch(extra: ["HIBOSS_DEMO_SESSION": "1"], arguments: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ])
        let field = app.textFields["session-reply-draft"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertTrue(field.isHittable)
        XCTAssertLessThanOrEqual(field.frame.maxX, app.frame.maxX)
        XCTAssertTrue(app.buttons["Message history"].isHittable)
        XCTAssertTrue(app.buttons["Session facts"].exists)
        XCTAssertTrue(app.buttons["Approve"].exists)
    }

    func testAutomaticDefaultNeverClaimsApproval() {
        let app = launch(extra: ["HIBOSS_DEMO_SESSION": "1", "HIBOSS_DEMO_OPTION_MEDIA": "automatic"])
        let banner = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS 'Default picked · not approval'"
        )).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'You chose'"))
            .firstMatch.exists)
    }

    func testSessionPanelKeepsQuestionnaireReachable() {
        let app = launch(extra: ["HIBOSS_DEMO_SESSION": "1", "HIBOSS_DEMO_NATIVE_PANEL": "1"])
        XCTAssertTrue(app.navigationBars["prod-release"].waitForExistence(timeout: 10))
        let panel = app.descendants(matching: .any)
            .matching(identifier: "session-panel-demo-panel").firstMatch
        for _ in 0..<8 where !panel.exists || !panel.isHittable { app.swipeUp() }
        XCTAssertTrue(panel.waitForExistence(timeout: 10))
        panel.tap()
        XCTAssertTrue(app.buttons["Submit checklist"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Panel actions"].exists)
    }

    func testReplyWithoutAnAgentMessageIsDisabledWithAnExplanation() {
        let app = launch(extra: ["HIBOSS_DEMO_SESSION": "1", "HIBOSS_DEMO_TEXT_ASK": "1"])
        XCTAssertTrue(app.staticTexts["No agent message yet. Reply will be available when one arrives."]
            .waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Send reply"].isEnabled)
        XCTAssertFalse(app.buttons["Attach from Box"].isEnabled)
    }

    func testBoxFiltersAndSearchIncludeOlderPages() {
        let app = launch()
        XCTAssertTrue(app.tabBars.buttons["Box"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Box"].tap()
        app.buttons["box-filter-agents"].tap()
        XCTAssertTrue(app.buttons["box-item-demo-agent-text"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["box-item-demo-image"].exists)
        app.buttons["box-filter-mine"].tap()
        XCTAssertTrue(app.buttons["box-item-demo-image"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["box-item-demo-agent-text"].exists)
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("Saved reference 20")
        XCTAssertTrue(app.buttons["box-item-demo-text-20"].waitForExistence(timeout: 10))
    }

    func testDecisionSheetOpensSessionAndKeepsFactsAndDefaultVisible() {
        let app = launch()
        XCTAssertTrue(app.buttons["home-message-c5"].waitForExistence(timeout: 10))
        app.buttons["home-message-c5"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["decision-provenance"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["decision-facts"].exists)
        let timing = app.scrollViews["decision-detail"].descendants(matching: .any)
            .matching(identifier: "decision-timing-c5").firstMatch
        for _ in 0..<8 where !timing.isHittable { app.swipeUp() }
        XCTAssertTrue(timing.label.contains("That is not approval."))
        let open = app.buttons["Open session"]
        for _ in 0..<8 where !open.isHittable { app.swipeUp() }
        open.tap()
        XCTAssertTrue(app.navigationBars["prod-release"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Attach from Box"].exists)
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        XCTAssertTrue(app.staticTexts["Refreshing. Showing earlier results."].waitForNonExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "v4-b-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
