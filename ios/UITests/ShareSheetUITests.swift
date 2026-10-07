// Drives the debug host's exact share form and retains simulator sheet screenshots.
// Exports ShareSheetUITests for preview, retained-note retry and missing-token cancellation.
// Dependencies: XCTest and the app's configured demo launch helper.

import XCTest

@MainActor
final class ShareSheetUITests: XCTestCase {
    func testSheetRetainsNoteAfterFailureAndRetryCompletes() {
        let app = launch("failure")
        XCTAssertTrue(app.staticTexts["https://example.com/design-reference"].waitForExistence(timeout: 10))
        let note = app.textFields["share-note"]
        let editor = note.exists ? note : app.textViews["share-note"]
        editor.tap()
        editor.typeText("Use this reference")
        app.navigationBars["Save to Box"].tap()
        attach(app, name: "hiboss-share-sheet")
        let save = app.buttons["share-save"]
        save.tap()
        XCTAssertTrue(app.staticTexts["share-error"].waitForExistence(timeout: 10))
        XCTAssertEqual(editor.value as? String, "Use this reference")
        attach(app, name: "hiboss-share-retry")
        save.tap()
        XCTAssertTrue(app.staticTexts["Saved to Box"].waitForExistence(timeout: 10))
    }

    func testMissingTokenAsksToOpenAppAndCancels() {
        let app = launch("disconnected")
        XCTAssertTrue(app.alerts["Open HiBoss to connect"].waitForExistence(timeout: 10))
        app.alerts.buttons["OK"].tap()
        XCTAssertFalse(app.buttons["share-save"].exists)
    }

    private func launch(_ state: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.configureDemoLaunch(["HIBOSS_DEMO_SHARE": state])
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchConfiguredDemo()
        return app
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
