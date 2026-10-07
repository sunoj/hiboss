// Regression coverage for option images across decision surfaces and settlement sources.
// Exports: OptionMediaUITests, with resolved detail and transcript screenshot attachments.
// Dependencies: XCTest, DemoLaunchSupport, DemoOptionMediaFixtures.

import XCTest

final class OptionMediaUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(state: String, route: [String: String], largeText: Bool = false) {
        app.configureDemoLaunch(route.merging(["HIBOSS_DEMO_OPTION_MEDIA": state]) { _, value in value })
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName",
                                    "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
    }

    func testResolvedDetailPreservesImagesAndZoom() {
        launch(state: "resolved", route: ["HIBOSS_DEMO_OPEN": "media-decision"])
        XCTAssertTrue(app.staticTexts["message-question"].waitForExistence(timeout: 10))
        assertImages()
        assertSelection(option: "Coastal view", automatic: false)
        shot("resolved-detail")
        assertZoom(option: "Coastal view")
    }

    func testResolvedSessionPreservesImagesAndZoom() {
        launch(state: "resolved", route: ["HIBOSS_DEMO_SESSION": "1"])
        assertImages()
        assertSelection(option: "Coastal view", automatic: false)
        shot("resolved-session")
        assertZoom(option: "Mountain view")
    }

    func testResolvedImagesRemainReachableAtAccessibilityTextSize() {
        launch(state: "resolved", route: ["HIBOSS_DEMO_OPEN": "media-decision"], largeText: true)
        assertImages()
        assertSelection(option: "Coastal view", automatic: false)
        let image = app.buttons["Open image for Coastal view"]
        for _ in 0..<6 where !image.isHittable { app.swipeUp() }
        XCTAssertTrue(image.isHittable)
        assertZoom(option: "Coastal view")
    }

    func testResolvedListPreservesImagesAndZoomWithoutOpeningDetail() {
        launch(state: "resolved", route: ["HIBOSS_DEMO_RESOLVED": "1"])
        XCTAssertTrue(app.navigationBars["Resolved"].waitForExistence(timeout: 10))
        assertImages()
        assertSelection(option: "Coastal view", automatic: false)
        assertZoom(option: "Coastal view")
        XCTAssertTrue(app.navigationBars["Resolved"].exists)
    }

    func testAutomaticImagesNeverClaimABossChoice() {
        for route in [["HIBOSS_DEMO_OPEN": "media-decision"],
                      ["HIBOSS_DEMO_SESSION": "1"], ["HIBOSS_DEMO_RESOLVED": "1"]] {
            launch(state: "automatic", route: route)
            assertImages()
            assertSelection(option: "Mountain view", automatic: true)
            XCTAssertFalse(app.staticTexts["Selected"].exists)
            app.terminate()
        }
    }

    func testPendingSessionImagesSurviveAnsweringInPlace() {
        launch(state: "pending", route: ["HIBOSS_DEMO_SESSION": "1"])
        assertImages()
        XCTAssertFalse(app.staticTexts["Selected"].exists)
        app.buttons["Mountain view"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["transcript-answer-media-decision"]
            .waitForExistence(timeout: 8))
        assertImages()
        assertSelection(option: "Mountain view", automatic: false)
        assertZoom(option: "Mountain view")
    }

    func testPendingHomeAndDetailStillShowImages() {
        launch(state: "pending", route: [:])
        assertImages()
        assertZoom(option: "Coastal view")
        app.buttons["home-message-media-decision"].tap()
        XCTAssertTrue(app.staticTexts["message-question"].waitForExistence(timeout: 8))
        assertImages()
        assertZoom(option: "Mountain view")
    }

    private func assertImages() {
        for option in ["Coastal view", "Mountain view"] {
            XCTAssertTrue(app.buttons["Open image for \(option)"].waitForExistence(timeout: 10),
                          "option media must remain visible")
        }
    }

    private func assertSelection(option: String, automatic: Bool) {
        let image = app.buttons["Open image for \(option)"]
        XCTAssertEqual(image.value as? String, automatic ? "Auto-selected" : "Selected")
        let other = option == "Coastal view" ? "Mountain view" : "Coastal view"
        XCTAssertNotEqual(app.buttons["Open image for \(other)"].value as? String,
                          automatic ? "Auto-selected" : "Selected")
    }

    private func assertZoom(option: String) {
        app.buttons["Open image for \(option)"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.images["option-media-zoom-image"].waitForExistence(timeout: 20))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForNonExistence(timeout: 5))
    }

    private func shot(_ name: String) {
        for option in ["Coastal view", "Mountain view"] {
            XCTAssertTrue(app.images["option-media-image-\(option)"].waitForExistence(timeout: 20))
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
