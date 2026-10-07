// Screenshot and routing coverage for panels, sample forms, device requests and option images.
// Exports: UXSurfaceUITests; every attachment is retained for the UX tour.
// Dependencies: XCTest and DemoLaunchSupport; uses the shell's production router.

import XCTest

final class UXSurfaceUITests: XCTestCase {
    private var app: XCUIApplication!
    private var prefix: String { ProcessInfo.processInfo.environment["UX_TOUR_PREFIX"] ?? "" }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ extra: [String: String]) {
        app.configureDemoLaunch(extra)
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchConfiguredDemo()
    }

    func testPanelNotificationOpensSampleIntakeForm() {
        launch(["HIBOSS_PANELS_DEMO": "1", "HIBOSS_DEMO_PANEL_OPEN": "research-intake.json"])
        XCTAssertTrue(app.navigationBars["Research intake"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Research question"].waitForExistence(timeout: 5))
        shot("en-20-panel-form")
        app.swipeUp()
        shot("en-21-panel-form-bottom")
        app.buttons["Done"].firstMatch.tap()
        let wall = app.staticTexts["Live panels"]
        for _ in 0..<10 where !wall.isHittable { app.swipeUp() }
        XCTAssertTrue(wall.isHittable)
        shot("en-22-panel-wall")
    }

    func testDeviceNotificationOpensTheMatchingReview() {
        launch(["HIBOSS_DEMO_JOIN_REQUEST": "jr-build"])
        XCTAssertTrue(app.navigationBars["Device Request"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Name, build-box-2"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["join-request.code"].label, "Verification code 4 8 2 9 1 3")
        XCTAssertTrue(app.buttons["Approve"].exists)
        shot("en-23-device-notification")
    }

    func testOptionImagesOpenFromHomeAndRemainInDetail() {
        launch(["HIBOSS_DEMO_OPTION_MEDIA": "1"])
        let image = app.buttons["Open image for Coarse grid"]
        XCTAssertTrue(image.waitForExistence(timeout: 10))
        for label in ["Coarse grid", "Fine grid"] {
            XCTAssertEqual(app.buttons["Open image for \(label)"].value as? String, "Image available")
        }
        shot("en-24-home-option-images")
        image.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.images["option-image-loaded-Coarse grid"].exists)
        shot("en-25-option-image-zoom")
        app.buttons["Done"].tap()
        app.buttons["home-message-c5"].tap()
        XCTAssertTrue(app.staticTexts["message-question"].waitForExistence(timeout: 5))
        XCTAssertTrue(image.exists)
        XCTAssertLessThanOrEqual(image.frame.maxX, app.frame.maxX)
        shot("en-26-detail-option-images")
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = prefix + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
