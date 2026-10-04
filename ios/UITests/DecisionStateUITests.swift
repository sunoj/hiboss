// Visible decision and account states: auto-selected history and transcript, in-flight replies,
// pairing expiry, sign-out and stale lists (Messages and Progress).
// Exports: DecisionStateUITests (demo mode, English).
// Dependencies: XCTest, DemoLaunchSupport.

import XCTest

final class DecisionStateUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ extra: [String: String] = [:]) {
        app.configureDemoLaunch(extra)
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    private func openSettingsRow(_ title: String) {
        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let row = app.buttons[title].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "missing Settings row \(title)")
        row.tap()
    }

    func testTimeoutDefaultIsNotShownAsTheBossChoice() {
        launch(["HIBOSS_DEMO_OPEN": "a1"])
        XCTAssertTrue(app.staticTexts["message-question"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Auto-selected when time ran out"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Auto-selected"].exists)
        XCTAssertFalse(app.staticTexts["Selected"].exists, "a server default is not a selection")
        XCTAssertFalse(app.staticTexts["Answered on System"].exists)
        XCTAssertFalse(app.staticTexts["Answered on API"].exists, "the demo reply is the historical api-source shape")
    }

    func testAutomaticReplyInTheTranscriptIsNotTheBossSpeaking() {
        launch(["HIBOSS_DEMO_OPEN": "a1"])
        let session = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'View session'")).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 10))
        session.tap()
        let automatic = app.descendants(matching: .any)["session-automatic-reply"]
        XCTAssertTrue(automatic.waitForExistence(timeout: 8), "the timeout default has its own row")
        XCTAssertTrue(automatic.label.contains("Auto-selected when time ran out"), automatic.label)
        let answer = app.descendants(matching: .any)["transcript-answer-a1"]
        XCTAssertTrue(answer.label.contains("Auto-selected when time ran out"), answer.label)
        XCTAssertFalse(app.descendants(matching: .any)["session-bubble-outgoing"].exists,
                       "no boss bubble claims the automatic answer")
    }

    func testInFlightReplyDisablesTheButtonsOnHomeAndInDetail() {
        launch(["HIBOSS_DEMO_REPLY_DELAY_MS": "8000"])
        let fine = app.buttons["Fine grid"].firstMatch
        XCTAssertTrue(fine.waitForExistence(timeout: 10))
        XCTAssertTrue(fine.isEnabled)
        fine.tap()
        let coarse = app.buttons["Coarse grid"].firstMatch
        let disabled = NSPredicate(format: "isEnabled == false")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: disabled, evaluatedWith: coarse)], timeout: 3), .completed,
                       "Home disables every option while the reply is in flight")
        XCTAssertFalse(fine.isEnabled)

        app.buttons["home-message-c5"].tap()
        XCTAssertTrue(app.staticTexts["message-question"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Coarse grid"].firstMatch.isEnabled, "detail reads the same in-flight state")
        XCTAssertFalse(app.buttons["Fine grid"].firstMatch.isEnabled)
        XCTAssertTrue(app.staticTexts["Selected"].waitForExistence(timeout: 15), "the one reply lands")
    }

    func testExpiredPairingCodeOffersAFreshCode() {
        launch(["HIBOSS_DEMO_PAIRING_TTL": "2"])
        openSettingsRow("Pair another device")
        XCTAssertTrue(app.buttons["Copy Link"].waitForExistence(timeout: 5), "a code is issued")
        let fresh = app.buttons["Request a fresh code"]
        XCTAssertTrue(fresh.waitForExistence(timeout: 6), "expiry offers a fresh code without leaving the screen")
        fresh.tap()
        XCTAssertTrue(app.buttons["Copy Link"].waitForExistence(timeout: 5), "a fresh code replaces the expired one")
    }

    func testSignOutAsksBeforeDeletingTheToken() {
        launch()
        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let signOut = app.buttons["settings-sign-out"]
        for _ in 0..<6 where !signOut.isHittable { app.swipeUp() }
        signOut.tap()
        XCTAssertTrue(app.staticTexts["Sign out of HiBoss?"].waitForExistence(timeout: 5))
        // iOS presents the dialog as an anchored popover with no Cancel row; tapping outside cancels.
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.exists { cancel.tap() } else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap() }
        XCTAssertTrue(app.staticTexts["Sign out of HiBoss?"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 5), "cancel keeps the session")
        XCTAssertFalse(app.textFields["server-url-field"].exists)
    }

    func testFailedRefreshKeepsRowsAndSaysTheyAreStale() {
        launch(["HIBOSS_DEMO_REFRESH_FAILS": "1"])
        let messages = app.tabBars.buttons["Messages"]
        XCTAssertTrue(messages.waitForExistence(timeout: 10))
        messages.tap()
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["list-stale-banner"].exists)
        Thread.sleep(forTimeInterval: 5)
        pullToRefresh(app)
        XCTAssertTrue(app.descendants(matching: .any)["list-stale-banner"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.cells.firstMatch.exists, "earlier rows stay visible")
    }

    func testFailedProgressRefreshKeepsPostsAndSaysTheyAreStale() {
        launch(["HIBOSS_DEMO_REFRESH_FAILS": "1"])
        let progress = app.tabBars.buttons["Progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        progress.tap()
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["list-stale-banner"].exists)
        Thread.sleep(forTimeInterval: 5)
        pullToRefresh(app)
        XCTAssertTrue(app.descendants(matching: .any)["list-stale-banner"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.cells.firstMatch.exists, "earlier posts stay visible")
    }
}
