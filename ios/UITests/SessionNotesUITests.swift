// Exercises session notes independently of message replies in configured demo mode.
// Exports SessionNotesUITests, retaining list and compose screenshot evidence.
// Dependencies: XCTest and DemoLaunchSupport.

import XCTest

final class SessionNotesUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testComposeNoteAndSeeUnreadReceipt() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Unread"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Read"].exists)
        captureDemoScreenshot(app, name: "session-notes-light", test: self)
        let field = app.textFields["session-note-body"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["send-session-note"].isEnabled)
        captureDemoScreenshot(app, name: "session-note-compose-light", test: self)
        field.tap()
        field.typeText("Please verify the changelog.")
        app.buttons["send-session-note"].tap()
        XCTAssertTrue(app.staticTexts["Please verify the changelog."].waitForExistence(timeout: 10))
        XCTAssertEqual(field.value as? String, "Write a note…")
    }

    @MainActor
    func testComposeImageNoteInLightAndDark() {
        for appearance in ["Light", "Dark"] {
            let app = launch([:], appearance: appearance)
            XCTAssertTrue(app.buttons["session-note-image"].firstMatch.waitForExistence(timeout: 10))
            captureDemoScreenshot(app, name: "notes-images-\(appearance)", test: self)
            app.buttons["Add images"].tap()
            let photo = app.images.matching(NSPredicate(format: "label CONTAINS 'Photo'")).firstMatch
            XCTAssertTrue(photo.waitForExistence(timeout: 10))
            photo.tap()
            let add = app.buttons["Add"]
            if add.exists { add.tap() }
            XCTAssertTrue(app.buttons["Remove image"].firstMatch.waitForExistence(timeout: 10))
            captureDemoScreenshot(app, name: "notes-thumbnails-\(appearance)", test: self)
            XCTAssertTrue(app.buttons["send-session-note"].isEnabled)
            let before = app.buttons.matching(identifier: "session-note-image").count
            app.buttons["send-session-note"].tap()
            let sent = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.buttons.matching(identifier: "session-note-image").count > before
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [sent], timeout: 10), .completed)
            XCTAssertFalse(app.buttons["Remove image"].exists)
            app.terminate()
        }
    }

    func testViewerCanReadButCannotCompose() {
        let app = launch(["HIBOSS_DEMO_NOTE_VIEWER": "1"])
        XCTAssertTrue(app.staticTexts["Unread"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["session-note-body"].exists)
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
        XCTAssertTrue(app.buttons["session-notes"].waitForExistence(timeout: 15))
        app.buttons["session-notes"].tap()
        XCTAssertTrue(app.staticTexts["Unread"].waitForExistence(timeout: 10))
        return app
    }
}
