// Exercises Box browsing, detail sharing, real file previews and deletion in offline demo mode.
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
        XCTAssertTrue(app.tabBars.buttons["Box"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Box"].tap()
    }

    func testAgentProvenanceAppearsInRowAndDetailWhileBossItemsHaveNoBadge() {
        let agent = app.buttons["box-item-demo-agent-text"]
        XCTAssertTrue(agent.waitForExistence(timeout: 10))
        XCTAssertTrue(agent.label.contains("Agents · Researcher"))
        XCTAssertTrue(app.buttons["box-item-demo-image"].exists)
        XCTAssertFalse(app.buttons["box-item-demo-image"].staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH 'Agents'")).firstMatch.exists)
        screenshot("box-agent-provenance-list")
        agent.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@", "Agents · Researcher")).firstMatch.waitForExistence(timeout: 5))
        screenshot("box-agent-provenance-detail")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["box-item-demo-text"].tap()
        XCTAssertTrue(app.staticTexts["A passage to keep"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Agents'")).firstMatch.exists)
    }

    func testBoxListOpensImageVideoAndSelectableTextThenDeletes() {
        XCTAssertEqual(app.tabBars.buttons.count, 4)
        let image = app.buttons["box-item-demo-image"]
        XCTAssertTrue(image.waitForExistence(timeout: 10))
        screenshot("box-segment")
        image.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.images["media-viewer-image"].waitForExistence(timeout: 10))
        assertMediaPinchZoom(app)
        screenshot("box-image-viewer")
        app.buttons["Close"].tap()
        let text = app.buttons["box-item-demo-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.tap()
        XCTAssertTrue(app.staticTexts["A passage to keep"].firstMatch.waitForExistence(timeout: 5))
        app.staticTexts["A passage to keep"].firstMatch.press(forDuration: 1)
        XCTAssertTrue(app.menuItems["Copy"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        let video = app.buttons["box-item-demo-video"]
        XCTAssertTrue(video.waitForExistence(timeout: 5))
        video.tap()
        XCTAssertTrue(app.descendants(matching: .any)["media-viewer-video"].waitForExistence(timeout: 10))
        screenshot("box-video-viewer")
        app.buttons["Close"].tap()
        text.press(forDuration: 1)
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.alerts["Delete A passage to keep?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Delete"].tap()
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
        app.tabBars.buttons["Today"].tap()
        app.tabBars.buttons["Box"].tap()
        XCTAssertTrue(app.tabBars.buttons["Box"].isSelected)
    }

    func testFileRowShowsNameAndSizeAndOpensDownloadedQuickLookPreview() {
        let file = app.buttons["box-item-demo-file"]
        for _ in 0..<4 where !file.isHittable { app.swipeUp() }
        XCTAssertTrue(file.waitForExistence(timeout: 5))
        XCTAssertTrue(file.staticTexts["Reference.txt"].exists)
        XCTAssertTrue(file.label.contains("23 bytes"))
        screenshot("box-file-row")
        file.tap()
        XCTAssertTrue(app.scrollViews["box-detail"].waitForExistence(timeout: 5))
        let open = app.buttons["Open file"]
        for _ in 0..<6 where !open.isHittable { app.swipeUp() }
        open.tap()
        let close = app.buttons["QLOverlayDoneButtonAccessibilityIdentifier"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertTrue(app.textViews["A saved reference file."].waitForExistence(timeout: 5))
        screenshot("box-file-preview")
        close.tap()
        XCTAssertTrue(app.scrollViews["box-detail"].waitForExistence(timeout: 5))
    }

    func testFileWithoutQuickLookPreviewOpensNativeShareSheet() {
        app.terminate()
        app.configureDemoLaunch(["HIBOSS_DEMO_BOX_FILE": "unsupported"])
        app.launchConfiguredDemo()
        XCTAssertTrue(app.tabBars.buttons["Box"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Box"].tap()
        let file = app.buttons["box-item-demo-file"]
        for _ in 0..<4 where !file.isHittable { app.swipeUp() }
        XCTAssertTrue(file.waitForExistence(timeout: 5))
        file.tap()
        XCTAssertTrue(app.scrollViews["box-detail"].waitForExistence(timeout: 5))
        let open = app.buttons["Open file"]
        for _ in 0..<6 where !open.isHittable { app.swipeUp() }
        open.tap()
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

extension BoxUITests {
    func testTextDetailSharesTextAndCapturesDetail() {
        app.buttons["box-item-demo-text"].tap()
        XCTAssertTrue(app.scrollViews["box-detail"].waitForExistence(timeout: 5))
        screenshot("box-detail-text")
        let share = app.buttons["box-detail-share"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        XCTAssertTrue(share.isHittable)
        share.tap()
        XCTAssertTrue(app.cells["Copy"].waitForExistence(timeout: 5))
        let caption = app.otherElements["ActivityListView"].otherElements["LP.CaptionBar.BottomCaption"]
        XCTAssertTrue(caption.waitForExistence(timeout: 5))
        XCTAssertEqual(caption.label, "A passage to keep")
    }

    func testLinkDetailSharesURLAndCapturesDetail() {
        app.buttons["box-item-demo-link"].tap()
        XCTAssertTrue(app.scrollViews["box-detail"].waitForExistence(timeout: 5))
        screenshot("box-detail-link")
        app.buttons["box-detail-share"].tap()
        XCTAssertTrue(app.cells["Copy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.cells["Open in Safari"].exists)
    }

    func testPDFDetailShowsFirstPageOpensFullPreviewAndSharesOriginal() {
        openDemoFile(["HIBOSS_DEMO_BOX_FILE": "pdf"])
        assertPDFReady()
        screenshot("box-detail-pdf")
        app.buttons["box-file-preview"].tap()
        let close = app.buttons["QLOverlayDoneButtonAccessibilityIdentifier"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Box PDF reference"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Second reference page"].exists)
        screenshot("box-pdf-full-preview")
        close.tap()
        app.buttons["box-detail-share"].tap()
        XCTAssertTrue(app.cells["Save to Files"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "Reference")).firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "PDF")).firstMatch.exists)
    }

    func testPDFDownloadShowsProgressFailureAndRetry() {
        openDemoFile(["HIBOSS_DEMO_BOX_FILE": "pdf",
                      "HIBOSS_DEMO_BOX_MEDIA_DELAY_MS": "3000",
                      "HIBOSS_DEMO_BOX_MEDIA_FAILURE": "demo-file"])
        XCTAssertTrue(app.staticTexts["Loading Box media…"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Retry"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Open file"].exists)
        XCTAssertFalse(app.buttons["box-detail-share"].isEnabled)
        app.buttons["Retry"].tap()
        assertPDFReady()
        XCTAssertTrue(app.buttons["Open file"].firstMatch.isEnabled)
    }

    func testLockedPDFKeepsOpenAndShareWithoutRetry() {
        openDemoFile(["HIBOSS_DEMO_BOX_FILE": "locked-pdf"])
        XCTAssertTrue(app.buttons["box-file-preview"].waitForExistence(timeout: 10))
        assertPreviewValue("Locked PDF")
        XCTAssertTrue(app.buttons["box-detail-share"].isEnabled)
        XCTAssertFalse(app.buttons["Retry"].exists)
        screenshot("box-locked-pdf")
        app.buttons["box-file-preview"].tap()
        XCTAssertTrue(app.buttons["QLOverlayDoneButtonAccessibilityIdentifier"].waitForExistence(timeout: 10))
    }

    func testCorruptPDFKeepsOpenDisablesShareWithoutRetry() {
        openDemoFile(["HIBOSS_DEMO_BOX_FILE": "corrupt-pdf"])
        assertPreviewValue("PDF preview unavailable")
        XCTAssertTrue(app.buttons["box-file-preview"].isEnabled)
        XCTAssertFalse(app.buttons["box-detail-share"].isEnabled)
        XCTAssertFalse(app.buttons["Retry"].exists)
    }

    func testImageDetailSharesOriginalDownloadedFile() {
        assertMediaDetailSharesFile("image")
        let sheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        let title = sheet.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@ OR label == %@", "Layout reference", "Layout reference.png")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        screenshot("box-image-share-human-filename")
    }

    func testVideoDetailSharesOriginalDownloadedFile() { assertMediaDetailSharesFile("video") }

    private func assertMediaDetailSharesFile(_ kind: String) {
        app.buttons["box-item-demo-\(kind)"].tap()
        XCTAssertTrue(app.buttons["media-viewer-info"].waitForExistence(timeout: 10))
        app.buttons["media-viewer-info"].tap()
        XCTAssertTrue(app.buttons["box-detail-share"].waitForExistence(timeout: 5))
        app.buttons["box-detail-share"].tap()
        XCTAssertTrue(app.cells["Save to Files"].waitForExistence(timeout: 10))
    }

    private func assertPDFReady() {
        assertPreviewValue("PDF")
    }

    private func assertPreviewValue(_ value: String) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value),
                                               object: app.buttons["box-file-preview"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
    }

    private func openDemoFile(_ environment: [String: String]) {
        app.terminate()
        app.configureDemoLaunch(environment)
        app.launchConfiguredDemo()
        XCTAssertTrue(app.tabBars.buttons["Box"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Box"].tap()
        let file = app.buttons["box-item-demo-file"]
        for _ in 0..<4 where !file.isHittable { app.swipeUp() }
        XCTAssertTrue(file.waitForExistence(timeout: 5))
        file.tap()
        XCTAssertTrue(app.scrollViews["box-detail"].waitForExistence(timeout: 5))
    }
}
