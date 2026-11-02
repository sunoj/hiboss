// Exercises session notes independently of message replies in configured demo mode.
// Exports SessionNotesUITests, retaining list and compose screenshot evidence.
// Dependencies: XCTest and DemoLaunchSupport.

import XCTest

@MainActor
final class SessionNotesUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testComposeNoteAndSeeUnreadReceipt() {
        let app = launch()
        revealNotes(app)
        captureDemoScreenshot(app, name: "session-notes-light", test: self)
        let field = app.textFields["session-note-body"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["send-session-note"].isEnabled)
        captureDemoScreenshot(app, name: "session-note-compose-light", test: self)
        field.tap()
        field.typeText("Please verify the changelog.")
        app.buttons["send-session-note"].tap()
        for _ in 0..<12 where !app.staticTexts["Please verify the changelog."].isHittable { app.swipeDown() }
        XCTAssertTrue(app.staticTexts["Please verify the changelog."].waitForExistence(timeout: 10))
        XCTAssertEqual(field.value as? String, "Write a note…")
    }

    @MainActor
    func testComposeImageNoteInLightAndDark() {
        for appearance in ["Light", "Dark"] {
            let app = launch([:], appearance: appearance)
            revealNotes(app)
            XCTAssertTrue(app.buttons["session-note-image"].firstMatch.waitForExistence(timeout: 10))
            captureDemoScreenshot(app, name: "notes-images-\(appearance)", test: self)
            app.buttons["Add images"].tap()
            let photo = app.images.matching(NSPredicate(format: "label CONTAINS 'Photo'")).firstMatch
            XCTAssertTrue(photo.waitForExistence(timeout: 10))
            photo.tap()
            let add = app.buttons["Add"]
            if add.exists { add.tap() }
            XCTAssertTrue(app.buttons["Remove image"].firstMatch.waitForExistence(timeout: 10))
            XCTAssertGreaterThanOrEqual(app.buttons["Remove image"].firstMatch.frame.width, 44)
            XCTAssertGreaterThanOrEqual(app.buttons["Remove image"].firstMatch.frame.height, 44)
            captureDemoScreenshot(app, name: "notes-thumbnails-\(appearance)", test: self)
            XCTAssertTrue(app.buttons["send-session-note"].isEnabled)
            app.buttons["send-session-note"].tap()
            let sent = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                !app.buttons["Remove image"].exists
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [sent], timeout: 10), .completed)
            for _ in 0..<12 { app.swipeDown() }
            XCTAssertTrue(app.buttons["session-note-image"].firstMatch.waitForExistence(timeout: 10))
            captureDemoScreenshot(app, name: "session-inline-sent-image-\(appearance)", test: self)
            app.terminate()
        }
    }

    @MainActor
    func testRepliesFollowTheirNoteInLightAndDark() {
        for appearance in ["Light", "Dark"] {
            let app = launch([:], appearance: appearance)
            let note = app.staticTexts["Keep the rollout small for the first hour."]
            let first = app.staticTexts["The small rollout is underway."]
            let quote = app.staticTexts["Reply to note: Keep the rollout small for the first hour."]
            for _ in 0..<6 where !note.isHittable { app.swipeDown() }
            XCTAssertTrue(note.isHittable)
            XCTAssertTrue(first.isHittable)
            XCTAssertTrue(quote.exists)
            XCTAssertLessThan(first.frame.minY, note.frame.minY)
            captureDemoScreenshot(app, name: "notes-replies-\(appearance)", test: self)
            app.terminate()
        }
    }

    func testViewerCanReadButCannotCompose() {
        let app = launch(["HIBOSS_DEMO_NOTE_VIEWER": "1"])
        revealNotes(app)
        XCTAssertFalse(app.otherElements["session-reply-composer"].exists)
    }

    func testSessionWithoutReplyTargetStillAcceptsNote() {
        let app = launch(["HIBOSS_DEMO_NOTES_NO_MESSAGES": "1"])
        let field = app.textFields["session-note-body"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("A note without a reply target")
        app.buttons["send-session-note"].tap()
        XCTAssertTrue(app.staticTexts["A note without a reply target"].waitForExistence(timeout: 10))
    }

    func testFailedSendKeepsDraftAndShowsError() {
        let app = launch(["HIBOSS_DEMO_NOTE_FAILS": "1"])
        let field = app.textFields["session-note-body"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Keep this draft")
        app.buttons["send-session-note"].tap()
        XCTAssertTrue(app.staticTexts["Unable to send note"].waitForExistence(timeout: 10))
        XCTAssertEqual(field.value as? String, "Keep this draft")
        XCTAssertTrue(app.buttons["send-session-note"].isEnabled)
    }

    private func launch(_ extra: [String: String] = [:], appearance: String = "Light") -> XCUIApplication {
        let app = XCUIApplication()
        var environment = extra
        environment["HIBOSS_DEMO_SESSION"] = "1"
        app.configureDemoLaunch(environment)
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleInterfaceStyle", appearance]
        app.launchConfiguredDemo()
        if extra["HIBOSS_DEMO_NOTE_VIEWER"] != "1" {
            let mode = app.buttons["session-composer-mode"]
            XCTAssertTrue(mode.waitForExistence(timeout: 15))
            captureDemoScreenshot(app, name: "session-reply-mode-\(appearance)", test: self)
            mode.tap()
            app.buttons["Leave a note for session"].firstMatch.tap()
            XCTAssertTrue(app.textFields["session-note-body"].waitForExistence(timeout: 5))
        }
        return app
    }

    private func revealNotes(_ app: XCUIApplication) {
        let unread = app.staticTexts["Unread"]
        for _ in 0..<12 where !unread.isHittable { app.swipeUp() }
        XCTAssertTrue(unread.waitForExistence(timeout: 10))
    }
}
