// Covers session and Direct transcript geometry and captures appearance/localization comparisons.
// Exports SessionPageLayoutUITests; measurements use native accessibility frames in points.
// Dependencies: XCTest and DemoLaunchSupport with the sess-deploy demo fixture.

import XCTest

final class SessionPageLayoutUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testDirectRouteShowsHistoryWithoutConnectivityError() {
        let app = launch()
        openDirect(app)
        capture(app, "direct-route")
        XCTAssertTrue(app.descendants(matching: .any)["session-bubble-incoming"]
            .waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Retry"].exists)
        XCTAssertFalse(app.staticTexts["Can't reach the server"].exists)
        XCTAssertTrue(app.textFields["session-reply-draft"].isHittable)
        XCTAssertTrue(app.textFields["session-reply-draft"].isEnabled)
    }

    func testSessionDefaultGeometryPreservesTranscriptSpace() {
        let app = launch(session: true)
        XCTAssertTrue(app.textFields["session-reply-draft"].waitForExistence(timeout: 10))
        capture(app, "session-geometry")
        let target = app.staticTexts["session-reply-target"]
        XCTAssertLessThanOrEqual(composerFrame(app).height, 120)
        XCTAssertLessThanOrEqual(target.frame.height, 44)
        XCTAssertGreaterThanOrEqual(app.buttons["Attach from Box"].frame.height, 44)
        XCTAssertGreaterThanOrEqual(app.buttons["Send reply"].frame.height, 44)
        XCTAssertGreaterThanOrEqual(visibleTranscriptFrame(app).height / app.frame.height, 0.60)
        XCTAssertFalse(app.tabBars.firstMatch.isHittable)
        scrollToFacts(app)
        let facts = app.descendants(matching: .any)["session-facts"]
        XCTAssertTrue(facts.isHittable)
        XCTAssertLessThanOrEqual(facts.frame.height, 64)
        XCTAssertGreaterThanOrEqual(facts.frame.minY, app.navigationBars.firstMatch.frame.maxY)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == 'prod-release'")).count, 1)
        let card = app.descendants(matching: .any)["transcript-decision-c1"]
        XCTAssertFalse(card.staticTexts.matching(NSPredicate(format: "label CONTAINS 'release/v2.4'"))
            .firstMatch.exists)
    }

    func testEndedSessionShowsMessagesAndNeutralNote() {
        let app = XCUIApplication()
        app.configureDemoLaunch(["HIBOSS_DEMO_SESSION": "1", "HIBOSS_DEMO_TRANSCRIPT_UNAVAILABLE": "1"])
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchConfiguredDemo()
        XCTAssertTrue(app.staticTexts["session-history-note"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["session-history-note"].label,
                       "This session has ended. Showing its messages.")
        XCTAssertTrue(app.descendants(matching: .any)["transcript-decision-c1"].exists)
        XCTAssertTrue(app.buttons["Approve"].exists)
        XCTAssertFalse(app.buttons["Retry"].exists)
        capture(app, "ended-session")
    }

    func testCardsKeepOnlyAgentIdentityThatDiffersFromSession() {
        let app = XCUIApplication()
        app.configureDemoLaunch(["HIBOSS_DEMO_SESSION": "1",
                                 "HIBOSS_DEMO_SESSION_AGENT": "orchestrator-01"])
        app.launchConfiguredDemo()
        let card = app.descendants(matching: .any)["transcript-decision-c1"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertFalse(card.staticTexts["orchestrator-01"].exists)
        XCTAssertFalse(card.staticTexts.matching(NSPredicate(format: "label CONTAINS 'prod-release'")).firstMatch
            .exists)
        card.buttons["Approve"].tap()
        XCTAssertTrue(card.descendants(matching: .any)["transcript-answer-c1"].waitForExistence(timeout: 10))
        XCTAssertFalse(card.staticTexts["orchestrator-01"].exists)
        let other = app.descendants(matching: .any)["transcript-decision-c5"]
        for _ in 0..<8 where !other.isHittable { app.swipeDown() }
        XCTAssertTrue(other.staticTexts["worker-design"].exists)
    }

    func testSessionAndDirectScreenshotMatrix() {
        for appearance in ["Light", "Dark"] {
            for variant in ["en", "ax", "zh"] {
                let app = launch(appearance: appearance, variant: variant, session: true)
                XCTAssertTrue(app.textFields["session-reply-draft"].waitForExistence(timeout: 10))
                capture(app, "\(appearance)-\(variant)-session")
                scrollToFacts(app)
                capture(app, "\(appearance)-\(variant)-session-facts")
                if variant == "ax", app.buttons["Session facts"].exists {
                    expandFacts(app)
                    capture(app, "\(appearance)-\(variant)-session-facts-expanded")
                }
                app.terminate()
                let direct = launch(appearance: appearance, variant: variant)
                openDirect(direct, variant: variant)
                capture(direct, "\(appearance)-\(variant)-direct")
                direct.terminate()
            }
        }
    }

    func testAccessibilityFactsExpandWithoutClippingOrOverlappingMessages() {
        for appearance in ["Light", "Dark"] {
            let app = launch(appearance: appearance, variant: "ax", session: true)
            XCTAssertTrue(app.textFields["session-reply-draft"].waitForExistence(timeout: 10))
            scrollToFacts(app)
            expandFacts(app)
            capture(app, "\(appearance)-ax-facts-verified")
            app.terminate()
        }
    }

    private func expandFacts(_ app: XCUIApplication) {
        app.buttons["Session facts"].tap()
        let started = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Started '")).firstMatch
        XCTAssertTrue(started.waitForExistence(timeout: 5))
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let facts = self.frame(app.descendants(matching: .any)["session-facts"])
            let card = self.frame(app.descendants(matching: .any)["transcript-decision-c6"])
            // Accessibility bounds round by fractions of a point, including at shared edges.
            let tolerance: CGFloat = 0.5
            return started.isHittable && started.frame.maxY <= facts.maxY + tolerance
                && card.minY + tolerance >= facts.maxY
        }, object: nil)
        let result = XCTWaiter.wait(for: [settled], timeout: 5)
        capture(app, "facts-expansion")
        let facts = frame(app.descendants(matching: .any)["session-facts"])
        let card = frame(app.descendants(matching: .any)["transcript-decision-c6"])
        XCTAssertEqual(result, .completed, "facts: \(facts); started: \(started.frame); card: \(card)")
    }

    private func launch(appearance: String = "Light", variant: String = "en",
                        session: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.configureDemoLaunch(session ? ["HIBOSS_DEMO_SESSION": "1"] : [:])
        app.launchArguments = ["-AppleLanguages", variant == "zh" ? "(zh-Hans)" : "(en)",
                               "-AppleLocale", variant == "zh" ? "zh_CN" : "en_US",
                               "-AppleInterfaceStyle", appearance]
        if variant == "ax" {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName",
                                    "UICTContentSizeCategoryAccessibilityL"]
        }
        app.launchConfiguredDemo()
        return app
    }

    private func openDirect(_ app: XCUIApplication, variant: String = "en") {
        let sessions = app.tabBars.buttons[variant == "zh" ? "会话" : "Sessions"]
        XCTAssertTrue(sessions.waitForExistence(timeout: 10))
        sessions.tap()
        let row = app.buttons["activity-session-direct"]
        for _ in 0..<8 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.buttons[variant == "zh" ? "消息历史" : "Message history"]
            .waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Loading transcript…"].waitForNonExistence(timeout: 5))
    }

    private func scrollToFacts(_ app: XCUIApplication) {
        for _ in 0..<6 { app.swipeDown() }
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "session-page-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
        let frames = ["screen": app.frame,
                      "navigation": app.navigationBars.firstMatch.frame,
                      "facts": frame(app.descendants(matching: .any)["session-facts"]),
                      "target": frame(app.staticTexts["session-reply-target"]),
                      "composer": composerFrame(app),
                      "transcript": frame(app.scrollViews.firstMatch),
                      "visible-transcript": visibleTranscriptFrame(app),
                      "first-card": frame(app.descendants(matching: .any)["transcript-decision-c6"]),
                      "started": frame(app.staticTexts.matching(
                        NSPredicate(format: "label BEGINSWITH 'Started '")).firstMatch)]
        let values = frames.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "\n")
        let geometry = XCTAttachment(string: values)
        geometry.name = "geometry-\(name)"
        geometry.lifetime = .keepAlways
        add(geometry)
    }

    private func frame(_ element: XCUIElement) -> CGRect {
        element.exists ? element.frame : .zero
    }

    private func composerFrame(_ app: XCUIApplication) -> CGRect {
        let identified = app.descendants(matching: .any)["session-reply-composer"]
        if identified.exists { return identified.frame }
        let target = frame(app.staticTexts["session-reply-target"])
        let field = frame(app.textFields["session-reply-draft"])
        return CGRect(x: 0, y: target.minY - 12, width: app.frame.width,
                      height: field.maxY - target.minY + 24)
    }

    private func visibleTranscriptFrame(_ app: XCUIApplication) -> CGRect {
        let top = app.navigationBars.firstMatch.frame.maxY
        let bottom = composerFrame(app).minY
        let available = CGRect(x: 0, y: top, width: app.frame.width, height: max(0, bottom - top))
        return frame(app.scrollViews.firstMatch).intersection(available)
    }
}
