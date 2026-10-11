// Attachment coverage across message detail, Today and ordinary/decision transcript bubbles.
// Exports: MessageAttachmentUITests, including retained detail screenshot evidence.
// Dependencies: XCTest, DemoLaunchSupport and bundled DemoMessageAttachments fixtures.

import XCTest

final class MessageAttachmentUITests: XCTestCase {
    func testMarkdownAttachmentPreviewInLightAppearance() { assertMarkdownPreview("Light") }
    func testMarkdownAttachmentPreviewInDarkAppearance() { assertMarkdownPreview("Dark") }

    private func assertMarkdownPreview(_ appearance: String) {
        launch(["HIBOSS_DEMO_OPEN": "attachment-file"], fixture: "markdown", appearance: appearance)
        let file = app.descendants(matching: .any)["message-attachment-file"]
        XCTAssertTrue(file.waitForExistence(timeout: 10))
        let preview = app.buttons["message-attachment-markdown-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        guard preview.exists else { return }
        preview.tap()
        XCTAssertTrue(app.navigationBars["release-notes.md"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Release notes"].exists)
        XCTAssertTrue(app.staticTexts["Alpha"].exists)
        XCTAssertTrue(app.staticTexts["345"].exists)
        XCTAssertTrue(app.staticTexts["swift test"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "markdown-preview-\(appearance)"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["message-attachment-file"].waitForExistence(timeout: 5))
    }

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ route: [String: String], delay: String = "", fixture: String = "1",
                        appearance: String = "Light") {
        app.configureDemoLaunch(route.merging([
            "HIBOSS_DEMO_ATTACHMENTS": fixture, "HIBOSS_DEMO_MEDIA_DELAY_MS": delay,
        ]) { _, new in new })
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-AppleInterfaceStyle", appearance]
        app.launchConfiguredDemo()
    }

    func testDetailImageLoadsAndOpensFullScreen() {
        launch(["HIBOSS_DEMO_OPEN": "attachment-image"])
        let thumbnail = app.buttons["message-attachment-open"]
        XCTAssertTrue(thumbnail.waitForExistence(timeout: 15))
        let loading = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Loading image…")).firstMatch
        XCTAssertTrue(loading.waitForNonExistence(timeout: 15))
        XCTAssertFalse(app.buttons["message-attachment-retry"].exists)
        XCTAssertGreaterThan(thumbnail.frame.height, 44)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "en-message-detail-attachment"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        assertViewer(app.buttons["message-attachment-open"])
        XCTAssertTrue(app.staticTexts["message-question"].exists)
    }

    func testFileDetailShowsFilenameAndURLLink() {
        launch(["HIBOSS_DEMO_OPEN": "attachment-file"])
        let file = app.descendants(matching: .any)["message-attachment-file"]
        XCTAssertTrue(file.waitForExistence(timeout: 10))
        XCTAssertEqual(file.label, "release-notes.pdf")
        XCTAssertTrue(file.isHittable)
        XCTAssertGreaterThanOrEqual(file.frame.height, 44)
        file.tap()
        XCTAssertTrue(XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
            .wait(for: .runningForeground, timeout: 10))
    }

    func testTranscriptOrdinaryAndDecisionAttachmentsOpenViewer() {
        launch(["HIBOSS_DEMO_SESSION": "1"])
        let ordinary = app.descendants(matching: .any)["session-bubble-incoming"].firstMatch
        XCTAssertTrue(ordinary.waitForExistence(timeout: 10))
        assertViewer(ordinary.buttons["message-attachment-open"])
        let decision = app.descendants(matching: .any)["transcript-decision-attachment-decision"]
        XCTAssertTrue(decision.exists)
        assertViewer(decision.buttons["message-attachment-open"])
        XCTAssertTrue(app.descendants(matching: .any)["message-attachment-file"].exists)
    }

    func testHomeFullBodyIncludesAttachment() {
        launch([:])
        let decision = app.buttons["home-message-attachment-decision"]
        XCTAssertTrue(decision.waitForExistence(timeout: 10))
        XCTAssertTrue(decision.isHittable)
        decision.tap()
        let question = app.staticTexts["message-question"]
        XCTAssertTrue(question.waitForExistence(timeout: 5))
        XCTAssertEqual(question.label, "Approve the release banner?")
        assertViewer(app.buttons["message-attachment-open"])
        XCTAssertTrue(question.isHittable)
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(decision.waitForExistence(timeout: 5))
        XCTAssertTrue(decision.isHittable)
    }

    func testSlowImageOffersRetryAndViewerRemainsDismissible() {
        launch(["HIBOSS_DEMO_OPEN": "attachment-image"], delay: "60000")
        let retry = app.buttons["message-attachment-retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 15))
        XCTAssertEqual(retry.value as? String, "Image is still loading")
        retry.tap()
        XCTAssertTrue(retry.waitForNonExistence(timeout: 3))
        app.buttons["message-attachment-open"].tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Loading image…"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["message-question"].waitForExistence(timeout: 5))
    }

    func testFailedImageOffersLocalRetryAndDismissibleViewer() {
        launch(["HIBOSS_DEMO_OPEN": "attachment-image"], fixture: "failure")
        let retry = app.buttons["message-attachment-retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 15))
        XCTAssertEqual(retry.value as? String, "Image unavailable")
        retry.tap()
        XCTAssertTrue(retry.waitForExistence(timeout: 15))
        app.buttons["message-attachment-open"]
            .coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.15)).tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Image unavailable"].waitForExistence(timeout: 15))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["message-question"].waitForExistence(timeout: 5))
    }

    private func assertViewer(_ button: XCUIElement) {
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        let header = app.descendants(matching: .any).matching(identifier: "session-facts").firstMatch
        let composer = app.textFields["session-reply-draft"].firstMatch
        for _ in 0..<8 {
            if header.exists && button.frame.midY < header.frame.maxY + 24 {
                app.swipeDown()
            } else if composer.exists && button.frame.midY > composer.frame.minY - 24 {
                app.swipeUp()
            } else if !button.isHittable { app.swipeUp() }
            else { break }
        }
        XCTAssertTrue(button.isHittable)
        button.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(app.buttons["Close"].frame.height, 44)
        XCTAssertTrue(app.images["release-banner.png"].waitForExistence(timeout: 15))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Close"].waitForNonExistence(timeout: 5))
    }
}
