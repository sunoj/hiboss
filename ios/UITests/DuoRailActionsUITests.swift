// The folded Duo's session page: the transcript keeps most of the height; jump-to-live and the
// note-target picker sit on the side rail. Exports DuoRailActionsUITests (skipped off the Duo).
// Dependencies: XCTest and DemoLaunchSupport with the sess-deploy and threads demo fixtures.

import XCTest

@MainActor
final class DuoRailActionsUITests: XCTestCase {
    /// The folded Duo's outer display, the only simulator that draws the side rail.
    private static let foldedDuo = CGSize(width: 466, height: 678)

    override func setUpWithError() throws { continueAfterFailure = false }

    /// The boss's layout: a note being written, scrolled up so "Jump to live" applies. It captures
    /// on any device (the comparison shots) and measures only on the Duo.
    func testScrolledUpTranscriptKeepsMostOfTheHeight() throws {
        let app = launchDemo(["HIBOSS_DEMO_SESSION": "1"])
        chooseNoteMode(app)
        app.swipeDown()
        XCTAssertTrue(app.buttons["jump-to-live"].waitForExistence(timeout: 5))
        captureDemoScreenshot(app, name: "duo-rail-scrolled-up", test: self)
        try XCTSkipUnless(app.frame.size == Self.foldedDuo, "needs the folded Duo's side rail")
        let composer = app.descendants(matching: .any)["session-reply-composer"].frame
        let transcript = visibleTranscript(app, composer: composer)
        let report = "transcript \(transcript.height) pt, composer \(composer.height) pt, "
            + "screen \(app.frame.height) pt"
        let measured = XCTAttachment(string: report)
        measured.name = "duo-rail-heights"
        measured.lifetime = .keepAlways
        add(measured)
        XCTAssertGreaterThanOrEqual(transcript.height, 470, report)
        XCTAssertLessThanOrEqual(composer.height, 110, report)
        XCTAssertFalse(app.staticTexts["0 / 4000"].exists, "the counter shows only near the limit")
    }

    /// Scrolled up to the session facts, the rail button returns to the live conversation: its start
    /// (the open decisions) moves up to the top, the facts header scrolling away under the title.
    func testJumpToLiveOnTheRailScrollsToTheNewestItem() throws {
        let app = try launch(["HIBOSS_DEMO_SESSION": "1"])
        let facts = app.descendants(matching: .any)["session-facts"]
        let start = app.staticTexts["Needs you"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        for _ in 0..<8 { app.swipeDown() }
        let before = "facts \(facts.frame), start \(start.frame)"
        let startY = start.frame.minY
        XCTAssertTrue(facts.isHittable, before)
        let jump = app.buttons["jump-to-live"]
        XCTAssertTrue(jump.waitForExistence(timeout: 5))
        assertOnRail(jump, app)
        XCTAssertTrue(jump.label.hasPrefix("Jump to live"), jump.label)
        jump.tap()
        XCTAssertTrue(jump.waitForNonExistence(timeout: 5))
        let after = "\(before) → facts \(facts.frame), start \(start.frame)"
        XCTAssertTrue(start.isHittable, after)
        XCTAssertLessThan(start.frame.minY, startY - 60, after)
        XCTAssertLessThan(start.frame.minY, 140, after)
    }

    func testNoteTargetPickerOnTheRailSwitchesTheTarget() throws {
        let app = try launch(["HIBOSS_DEMO_SESSION": "1"])
        let mode = app.buttons["session-composer-mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 15))
        assertOnRail(mode, app)
        XCTAssertEqual(mode.label, "Choose reply target")
        chooseNoteMode(app)
        XCTAssertEqual(mode.label, "Leave a note for session")
        XCTAssertFalse(app.textFields["session-reply-draft"].exists)
        mode.tap()
        let reply = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Custom answer to:'"
            + " OR label BEGINSWITH 'Replying to:'")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 5))
        reply.tap()
        XCTAssertTrue(app.textFields["session-reply-draft"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["session-note-body"].exists)
    }

    private func launch(_ environment: [String: String]) throws -> XCUIApplication {
        let app = launchDemo(environment)
        try XCTSkipUnless(app.frame.size == Self.foldedDuo, "needs the folded Duo's side rail")
        return app
    }

    private func launchDemo(_ environment: [String: String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.configureDemoLaunch(environment)
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchConfiguredDemo()
        XCTAssertTrue(app.buttons["Message history"].waitForExistence(timeout: 15))
        return app
    }

    private func chooseNoteMode(_ app: XCUIApplication) {
        let mode = app.buttons["session-composer-mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 15))
        mode.tap()
        app.buttons["Leave a note for session"].firstMatch.tap()
        XCTAssertTrue(app.textFields["session-note-body"].waitForExistence(timeout: 5))
    }

    /// The rail is the strip right of the content column, where the history button stacks too.
    /// XCUI reports system rail items smaller than their glass slot (history: 28×36), so the
    /// tap target is checked as at least the history button's and a slot pitch of 44 pt or more.
    private func assertOnRail(_ control: XCUIElement, _ app: XCUIApplication) {
        let history = app.buttons["Message history"].frame
        XCTAssertEqual(control.frame.midX, history.midX, accuracy: 8, "\(control.frame) in the rail column")
        XCTAssertFalse(control.frame.intersects(history), "\(control.frame) stacks apart from \(history)")
        let frames = "\(control.frame); history \(history)"
        XCTAssertGreaterThanOrEqual(control.frame.width, history.width, frames)
        XCTAssertGreaterThanOrEqual(control.frame.height, history.height, frames)
        XCTAssertGreaterThanOrEqual(abs(control.frame.midY - history.midY), 44, frames)
        XCTAssertTrue(control.isHittable)
    }

    private func visibleTranscript(_ app: XCUIApplication, composer: CGRect) -> CGRect {
        let top = app.navigationBars.firstMatch.frame.maxY
        let available = CGRect(x: 0, y: top, width: app.frame.width, height: max(0, composer.minY - top))
        return app.scrollViews["session-transcript"].frame.intersection(available)
    }
}
