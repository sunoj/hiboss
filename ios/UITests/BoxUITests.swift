// Exercises Activity Box browsing, opening, pagination and deletion in offline demo mode.
// Exports BoxUITests and retained simulator screenshots.
// Dependencies: XCTest and launchConfiguredDemo.

import XCTest

final class BoxUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.configureDemoLaunch()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchConfiguredDemo()
        XCTAssertTrue(app.tabBars.buttons["Activity"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Activity"].tap()
        app.segmentedControls.buttons["Box"].tap()
    }

    func testBoxListOpensImageVideoAndSelectableTextThenDeletes() {
        XCTAssertEqual(app.tabBars.buttons.count, 4)
        let image = app.buttons["box-item-demo-image"]
        XCTAssertTrue(image.waitForExistence(timeout: 10))
        screenshot("box-segment")
        image.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.images["Layout reference"].waitForExistence(timeout: 10))
        screenshot("box-image-viewer")
        app.buttons["Close"].tap()
        let text = app.buttons["box-item-demo-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.tap()
        XCTAssertTrue(app.staticTexts["A passage to keep"].waitForExistence(timeout: 5))
        app.staticTexts["A passage to keep"].press(forDuration: 1)
        XCTAssertTrue(app.menuItems["Copy"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        let video = app.buttons["box-item-demo-video"]
        XCTAssertTrue(video.waitForExistence(timeout: 5))
        video.tap()
        XCTAssertTrue(app.buttons["Unmute"].waitForExistence(timeout: 10))
        screenshot("box-video-viewer")
        app.buttons["Close"].tap()
        text.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(text.waitForNonExistence(timeout: 5))
        screenshot("box-after-delete")
    }

    func testBoxLoadsOlderPageAndKeepsSelectionAcrossTabs() {
        let more = app.buttons["box-load-more"]
        for _ in 0..<8 where !more.isHittable { app.swipeUp() }
        XCTAssertTrue(more.isHittable)
        more.tap()
        let last = app.buttons["box-item-demo-text-20"]
        for _ in 0..<4 where !last.isHittable { app.swipeUp() }
        XCTAssertTrue(last.waitForExistence(timeout: 5))
        XCTAssertFalse(more.exists)
        app.tabBars.buttons["Home"].tap()
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["Box"].isSelected)
    }

    func testFileRowShowsNameAndSizeAndOpensDownloadedQuickLookPreview() {
        let file = app.buttons["box-item-demo-file"]
        for _ in 0..<4 where !file.isHittable { app.swipeUp() }
        XCTAssertTrue(file.waitForExistence(timeout: 5))
        XCTAssertTrue(file.staticTexts["Reference.txt"].exists)
        XCTAssertTrue(file.staticTexts["23 bytes"].exists)
        screenshot("box-file-row")
        file.tap()
        let close = app.buttons["QLOverlayDoneButtonAccessibilityIdentifier"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertTrue(app.textViews["A saved reference file."].waitForExistence(timeout: 5))
        screenshot("box-file-preview")
        close.tap()
        XCTAssertTrue(app.scrollViews["box-text-detail"].waitForExistence(timeout: 5))
    }

    func testFileWithoutQuickLookPreviewOpensNativeShareSheet() {
        app.terminate()
        app.configureDemoLaunch(["HIBOSS_DEMO_BOX_FILE": "unsupported"])
        app.launchConfiguredDemo()
        XCTAssertTrue(app.tabBars.buttons["Activity"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Activity"].tap()
        app.segmentedControls.buttons["Box"].tap()
        let file = app.buttons["box-item-demo-file"]
        for _ in 0..<4 where !file.isHittable { app.swipeUp() }
        XCTAssertTrue(file.waitForExistence(timeout: 5))
        file.tap()
        XCTAssertTrue(app.cells["Copy"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.cells["Save to Files"].exists)
        screenshot("box-file-share-sheet")
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
