// Shared viewer behavior and light/dark English/Chinese screenshot coverage.
// Exports MediaViewerUITests for paging, captions, chrome, sharing, video and Markdown images.
// Dependencies: XCTest, demo fixtures and MediaViewerTestSupport.

import XCTest

final class MediaViewerUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ route: [String: String], language: String = "en", appearance: String = "Light") {
        app.configureDemoLaunch(route)
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", language,
                               "-AppleInterfaceStyle", appearance]
        app.launchConfiguredDemo()
    }

    func testOptionPagingStartsAtTappedImageAndUpdatesCaption() {
        launch(["HIBOSS_DEMO_OPTION_MEDIA": "pending", "HIBOSS_DEMO_OPEN": "media-decision"])
        openOption("Mountain view")
        XCTAssertEqual(app.staticTexts["media-viewer-counter"].label, "2 / 2")
        XCTAssertTrue(app.staticTexts["Fine detail in the mountain landscape."].exists)
        mediaZoomScroll(app).swipeRight()
        XCTAssertTrue(app.staticTexts["A wide view of the coastline."].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["media-viewer-counter"].label, "1 / 2")
        assertMediaPinchZoom(app)
        mediaZoomScroll(app).doubleTap()
        let fitted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'Fitted'"),
                                               object: mediaZoomScroll(app))
        XCTAssertEqual(XCTWaiter.wait(for: [fitted], timeout: 3), .completed)
        mediaZoomScroll(app).doubleTap()
        XCTAssertEqual(mediaZoomScroll(app).value as? String, "Zoomed")
    }

    func testSingleTapTogglesChromeAndShareUsesNativeSheet() {
        launch(["HIBOSS_DEMO_OPTION_MEDIA": "pending"])
        openOption("Coastal view")
        XCTAssertFalse(app.buttons["media-viewer-info"].exists)
        XCTAssertFalse(app.buttons["media-viewer-delete"].exists)
        let scroll = mediaZoomScroll(app)
        scroll.tap()
        XCTAssertTrue(app.buttons["media-viewer-close"].waitForNonExistence(timeout: 3))
        scroll.tap()
        let share = app.buttons["media-viewer-share"]
        XCTAssertTrue(share.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(share.frame.width, 44)
        XCTAssertGreaterThanOrEqual(share.frame.height, 44)
        share.tap()
        XCTAssertTrue(app.cells["Copy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.cells["Save Image"].exists || app.cells["Save to Files"].exists)
    }

    func testMarkdownDetailAndTranscriptImagesUseSharedZoom() {
        for route in [["HIBOSS_DEMO_OPEN": "markdown-report"], ["HIBOSS_DEMO_SESSION": "1"]] {
            launch(route.merging(["HIBOSS_DEMO_MARKDOWN": "1", "HIBOSS_DEMO_MARKDOWN_IMAGES": "1"]) {
                _, value in value
            })
            let image = app.buttons["markdown-media-open"].firstMatch
            XCTAssertTrue(app.staticTexts["House update"].firstMatch.waitForExistence(timeout: 10)
                          || app.staticTexts["message-question"].waitForExistence(timeout: 10))
            for _ in 0..<8 where !image.isHittable { app.swipeUp() }
            XCTAssertTrue(image.exists)
            image.tap()
            XCTAssertTrue(app.buttons["media-viewer-close"].waitForExistence(timeout: 5))
            assertMediaPinchZoom(app)
            app.terminate()
        }
    }

    func testMarkdownAttachmentImageUsesSharedZoom() {
        launch(["HIBOSS_DEMO_ATTACHMENTS": "markdown", "HIBOSS_DEMO_OPEN": "attachment-file"])
        let preview = app.buttons["message-attachment-markdown-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        preview.tap()
        let image = app.buttons["markdown-media-open"].firstMatch
        for _ in 0..<8 where !image.isHittable { app.swipeUp() }
        XCTAssertTrue(image.exists)
        image.tap()
        XCTAssertTrue(app.buttons["media-viewer-close"].waitForExistence(timeout: 5))
        assertMediaPinchZoom(app)
    }

    func testVideoAttachmentUsesSharedLoopingViewerAndShareSheet() {
        launch(["HIBOSS_DEMO_ATTACHMENTS": "video", "HIBOSS_DEMO_OPEN": "attachment-video"])
        let video = app.buttons["message-attachment-video-open"]
        XCTAssertTrue(video.waitForExistence(timeout: 10))
        video.tap()
        XCTAssertTrue(app.buttons["Unmute"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["media-viewer-video"].exists)
        app.buttons["media-viewer-share"].tap()
        XCTAssertTrue(app.cells["Save Video"].waitForExistence(timeout: 5)
                      || app.cells["Save to Files"].exists)
    }

    func testVideoAttachmentPinchReportsZoomed() {
        launch(["HIBOSS_DEMO_ATTACHMENTS": "video", "HIBOSS_DEMO_OPEN": "attachment-video"])
        let video = app.buttons["message-attachment-video-open"]
        XCTAssertTrue(video.waitForExistence(timeout: 10))
        video.tap()
        XCTAssertTrue(app.buttons["Unmute"].waitForExistence(timeout: 5))
        assertMediaPinchZoom(app)
    }

    func testFailedViewerImageCanRetryAndStillClose() {
        launch(["HIBOSS_DEMO_ATTACHMENTS": "failure", "HIBOSS_DEMO_OPEN": "attachment-image"])
        let image = app.buttons["message-attachment-open"]
        XCTAssertTrue(image.waitForExistence(timeout: 10))
        image.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.15)).tap()
        let retry = app.buttons["media-viewer-image-retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        retry.tap()
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["media-viewer-close"].isHittable)
        app.buttons["media-viewer-close"].tap()
        XCTAssertTrue(app.staticTexts["message-question"].waitForExistence(timeout: 5))
    }

    func testTodayDeliveredImageThumbnailUsesSharedZoom() {
        launch(["HIBOSS_DEMO_ATTACHMENTS": "1"])
        let delivered = app.staticTexts["Delivered"]
        XCTAssertTrue(delivered.waitForExistence(timeout: 10))
        for _ in 0..<8 where !delivered.isHittable { app.swipeUp() }
        let images = app.buttons.matching(identifier: "message-attachment-open")
        let thumbnail = images.allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(thumbnail)
        thumbnail?.tap()
        XCTAssertTrue(app.buttons["media-viewer-close"].waitForExistence(timeout: 5))
        assertMediaPinchZoom(app)
    }

    func testBoxImageFileUsesSharedZoom() {
        launch(["HIBOSS_DEMO_BOX_FILE": "image"])
        app.tabBars.buttons["Box"].tap()
        let file = app.buttons["box-item-demo-file"]
        XCTAssertTrue(file.waitForExistence(timeout: 10))
        for _ in 0..<6 where !file.isHittable { app.swipeUp() }
        file.tap()
        let open = app.buttons["Open file"]
        for _ in 0..<6 where !open.isHittable { app.swipeUp() }
        open.tap()
        XCTAssertTrue(app.buttons["media-viewer-close"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.images["media-viewer-image"].waitForExistence(timeout: 10))
        assertMediaPinchZoom(app)
    }

    func testTodayDecisionMarkdownImageOpensWithoutOpeningDetail() {
        launch(["HIBOSS_DEMO_OPTION_MEDIA": "pending", "HIBOSS_DEMO_MARKDOWN_IMAGES": "1"])
        let image = app.buttons["markdown-media-open"]
        XCTAssertTrue(image.waitForExistence(timeout: 10))
        image.tap()
        XCTAssertTrue(app.buttons["media-viewer-close"].waitForExistence(timeout: 5))
        assertMediaPinchZoom(app)
        app.buttons["media-viewer-close"].tap()
        XCTAssertTrue(app.buttons["home-message-media-decision"].isHittable)
        XCTAssertFalse(app.staticTexts["message-question"].exists)
    }

    func testProgressPagingKeepsPostSetAndStartsAtTappedItem() {
        launch(["HIBOSS_TAB": "progress"])
        let image = app.images["trailing still"].firstMatch
        for _ in 0..<12 where !image.isHittable { app.swipeUp() }
        XCTAssertTrue(image.isHittable)
        image.tap()
        XCTAssertTrue(app.buttons["media-viewer-close"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["media-viewer-counter"].label, "2 / 2")
        mediaZoomScroll(app).swipeRight()
        XCTAssertEqual(app.staticTexts["media-viewer-counter"].label, "1 / 2")
        assertMediaPinchZoom(app)
    }

    func testViewerScreenshotsInBothLanguagesAndAppearances() {
        for language in ["en", "zh-Hans"] {
            for appearance in ["Light", "Dark"] {
                launch(["HIBOSS_DEMO_OPTION_MEDIA": "pending"], language: language, appearance: appearance)
                openOption("Coastal view", language: language)
                XCTAssertEqual(app.staticTexts["media-viewer-counter"].label, "1 / 2")
                XCTAssertTrue(app.staticTexts["A wide view of the coastline."].exists)
                capture("\(language)-\(appearance)-option-set")
                let scroll = mediaZoomScroll(app)
                scroll.pinch(withScale: 2, velocity: 1)
                let expected = language == "en" ? "Zoomed" : "已放大"
                XCTAssertEqual(scroll.value as? String, expected)
                capture("\(language)-\(appearance)-image-zoomed")
                app.terminate()
                launch([:], language: language, appearance: appearance)
                app.tabBars.buttons.element(boundBy: 2).tap()
                let video = app.buttons["box-item-demo-video"]
                XCTAssertTrue(video.waitForExistence(timeout: 10))
                for _ in 0..<4 where !video.isHittable { app.swipeUp() }
                video.tap()
                let videoSurface = app.descendants(matching: .any)["media-viewer-video"]
                XCTAssertTrue(videoSurface.waitForExistence(timeout: 10))
                XCTAssertTrue(app.buttons["media-viewer-close"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.buttons["media-viewer-close"].isHittable)
                XCTAssertTrue(app.buttons["media-viewer-share"].isHittable)
                XCTAssertTrue(app.buttons["media-viewer-info"].isHittable)
                XCTAssertTrue(app.buttons["media-viewer-delete"].isHittable)
                XCTAssertTrue(app.descendants(matching: .any)["media-viewer-video"].exists)
                let loading = app.staticTexts[language == "en" ? "Loading video…" : "正在加载视频…"]
                XCTAssertTrue(loading.waitForNonExistence(timeout: 10))
                XCTAssertFalse(app.staticTexts[language == "en" ? "Video unavailable" : "视频暂不可用"].exists)
                capture("\(language)-\(appearance)-video")
                app.terminate()
            }
        }
    }

    private func openOption(_ label: String, language: String = "en") {
        let button = app.buttons[language == "en" ? "Open image for \(label)" : "打开「\(label)」的图片"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
        XCTAssertTrue(app.buttons["media-viewer-close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.images["media-viewer-image"].firstMatch.waitForExistence(timeout: 10))
    }

    private func capture(_ name: String) {
        let scroll = mediaZoomScroll(app)
        scroll.tap()
        XCTAssertTrue(app.buttons["media-viewer-close"].waitForNonExistence(timeout: 3))
        scroll.tap()
        XCTAssertTrue(app.buttons["media-viewer-close"].waitForExistence(timeout: 3))
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
