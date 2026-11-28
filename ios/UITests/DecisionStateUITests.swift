// Visible decision and account states: auto-selected history and transcript, in-flight replies,
// pairing expiry and copy confirmation, device requests, sign-out and stale lists.
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
        app.launchConfiguredDemo()
    }

    private func openSettingsRow(_ title: String) {
        let settings = app.buttons["today-settings"]
        XCTAssertTrue(settings.appears(timeout: 10))
        settings.tap()
        app.buttons["settings-devices"].tap()
        let row = app.buttons[title].firstMatch
        XCTAssertTrue(row.appears(timeout: 5), "missing Settings row \(title)")
        row.tap()
    }

    func testResolvedDecisionShowsAnsweringDevice() {
        launch(["HIBOSS_DEMO_OPEN": "media-decision", "HIBOSS_DEMO_OPTION_MEDIA": "resolved",
                "HIBOSS_DEMO_DEVICE_LABEL": "Ming's iPhone"])
        XCTAssertTrue(app.staticTexts["Answered on Ming's iPhone"].appears(timeout: 10))
        XCTAssertFalse(app.staticTexts["Answered on API"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "answered-device-ios"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testTimeoutDefaultIsNotShownAsTheBossChoice() {
        launch(["HIBOSS_DEMO_OPEN": "a1"])
        XCTAssertTrue(app.staticTexts["message-question"].appears(timeout: 10))
        XCTAssertTrue(app.staticTexts["Auto-selected when time ran out"].appears(timeout: 5))
        XCTAssertTrue(app.staticTexts["Auto-selected"].exists)
        XCTAssertFalse(app.staticTexts["Selected"].exists, "a server default is not a selection")
        XCTAssertFalse(app.staticTexts["Answered on System"].exists)
        XCTAssertFalse(app.staticTexts["Answered on API"].exists, "the demo reply is the historical api-source shape")
    }

    func testAutomaticReplyInTheTranscriptIsNotTheBossSpeaking() {
        launch(["HIBOSS_DEMO_OPEN": "a1"])
        let session = app.buttons["Open session"]
        XCTAssertTrue(session.appears(timeout: 10))
        for _ in 0..<8 where !session.isHittable { app.swipeUp() }
        session.tap()
        let automatic = app.descendants(matching: .any)["session-automatic-reply"]
        XCTAssertTrue(automatic.appears(timeout: 8), "the timeout default has its own row")
        let answer = automatic.descendants(matching: .any)["transcript-answer-a1"]
        XCTAssertTrue(answer.label.contains("Auto-selected when time ran out"), answer.label)
        XCTAssertTrue(answer.label.contains("Default picked · not approval"), answer.label)
        XCTAssertFalse(app.descendants(matching: .any)["session-bubble-outgoing"].exists,
                       "no boss bubble claims the automatic answer")
    }

    func testInFlightReplyDisablesTheButtonsOnHomeAndInDetail() {
        launch(["HIBOSS_DEMO_REPLY_DELAY_MS": "8000"])
        let fine = app.buttons["Fine grid"].firstMatch
        XCTAssertTrue(fine.appears(timeout: 10))
        XCTAssertTrue(fine.isEnabled)
        fine.tap()
        let coarse = app.buttons["Coarse grid"].firstMatch
        let disabled = NSPredicate(format: "isEnabled == false")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: disabled, evaluatedWith: coarse)], timeout: 3), .completed,
                       "Home disables every option while the reply is in flight")
        XCTAssertFalse(fine.isEnabled)

        app.buttons["home-message-c5"].tap()
        XCTAssertTrue(app.staticTexts["message-question"].appears(timeout: 5))
        XCTAssertFalse(app.buttons["Coarse grid"].firstMatch.isEnabled, "detail reads the same in-flight state")
        XCTAssertFalse(app.buttons["Fine grid"].firstMatch.isEnabled)
        XCTAssertTrue(app.staticTexts["Selected"].appears(timeout: 15), "the one reply lands")
    }

    func testExpiredPairingCodeOffersAFreshCode() {
        launch(["HIBOSS_DEMO_PAIRING_TTL": "2"])
        openSettingsRow("Pair another device")
        XCTAssertTrue(app.buttons["Copy Link"].appears(timeout: 5), "a code is issued")
        let fresh = app.buttons["Request a fresh code"]
        XCTAssertTrue(fresh.appears(timeout: 6), "expiry offers a fresh code without leaving the screen")
        fresh.tap()
        XCTAssertTrue(app.buttons["Copy Link"].appears(timeout: 5), "a fresh code replaces the expired one")
    }

    func testCopyLinkConfirmsTheCopy() {
        launch()
        openSettingsRow("Pair another device")
        let copy = app.buttons["Copy Link"]
        XCTAssertTrue(copy.appears(timeout: 5))
        copy.tap()
        XCTAssertTrue(app.buttons["Copied"].appears(timeout: 2), "the button confirms the copy")
        XCTAssertTrue(app.buttons["Copy Link"].appears(timeout: 5), "the confirmation is transient")
    }

    func testDeviceRequestWithoutACodeSaysWhyOnItsRow() {
        launch()
        openSettingsRow("Device Requests")
        let legacy = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'ci-runner'")).firstMatch
        XCTAssertTrue(legacy.appears(timeout: 5))
        XCTAssertTrue(legacy.label.contains("No verification code"), legacy.label)
        let approvable = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'build-box-2'")).firstMatch
        XCTAssertFalse(approvable.label.contains("No verification code"), approvable.label)
    }

    func testSignOutAsksBeforeDeletingTheToken() {
        launch()
        let settings = app.buttons["today-settings"]
        XCTAssertTrue(settings.appears(timeout: 10))
        settings.tap()
        let signOut = app.buttons["settings-sign-out"]
        for _ in 0..<6 where !signOut.isHittable { app.swipeUp() }
        signOut.tap()
        XCTAssertTrue(app.staticTexts["Sign out of HiBoss?"].appears(timeout: 5))
        // iOS presents the dialog as an anchored popover with no Cancel row; tapping outside cancels.
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.exists { cancel.tap() } else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap() }
        XCTAssertTrue(app.staticTexts["Sign out of HiBoss?"].disappears(timeout: 5))
        XCTAssertTrue(app.buttons["settings-sign-out"].appears(timeout: 5), "cancel keeps the session")
        XCTAssertFalse(app.textFields["server-url-field"].exists)
    }

    func testFailedRefreshKeepsRowsAndSaysTheyAreStale() {
        launch(["HIBOSS_DEMO_REFRESH_FAILS": "1"])
        let activity = app.tabBars.buttons["Sessions"]
        XCTAssertTrue(activity.appears(timeout: 10))
        activity.tap()
        app.openAllMessages()
        XCTAssertTrue(app.cells.firstMatch.appears(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["list-stale-banner"].exists)
        Thread.sleep(forTimeInterval: 5)
        // The persistent search field moves the list below the old screen-relative drag origin.
        app.cells.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
            .press(forDuration: 0.1,
                   thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        XCTAssertTrue(app.descendants(matching: .any)["list-stale-banner"].appears(timeout: 5))
        XCTAssertTrue(app.cells.firstMatch.exists, "earlier rows stay visible")
    }

    func testFailedProgressRefreshKeepsPostsAndSaysTheyAreStale() {
        // Initial posts must load during the demo's five-second success window.
        launch(["HIBOSS_DEMO_REFRESH_FAILS": "1", "HIBOSS_TAB": "progress"])
        let progress = app.tabBars.buttons["Progress"]
        XCTAssertTrue(progress.appears(timeout: 10))
        progress.tap()
        let post = app.images["wide landscape screenshot"].firstMatch
        let notice = app.staticTexts["list-stale-banner"]
        XCTAssertTrue(post.appears(timeout: 5))
        XCTAssertFalse(notice.exists)
        Thread.sleep(forTimeInterval: 5)
        pullToRefresh(app)
        XCTAssertTrue(notice.appears(timeout: 5))
        XCTAssertTrue(notice.label.hasPrefix("Couldn't refresh · showing posts loaded "))
        XCTAssertTrue(post.exists, "earlier posts stay visible")
        XCTAssertLessThan(notice.frame.maxY, post.frame.minY)
        let retry = app.buttons["Retry"].firstMatch
        XCTAssertTrue(retry.isHittable)
        retry.tap()
        XCTAssertTrue(post.exists)
    }
}
