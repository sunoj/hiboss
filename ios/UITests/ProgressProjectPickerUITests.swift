// Progress project menu regression coverage for names, counts and filtering.
// Exports ProgressProjectPickerUITests; depends on XCTest and offline demo fixtures.

import XCTest

@MainActor
final class ProgressProjectPickerUITests: XCTestCase {
    func testNoAvatarProjectCanBeSelectedAndAllProjectsRestored() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.configureDemoLaunch(["HIBOSS_TAB": "progress"])
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleInterfaceStyle", "Dark"]
        app.launchConfiguredDemo()
        let filter = app.buttons["Filter by project"]
        XCTAssertTrue(filter.waitForExistence(timeout: 10))
        XCTAssertTrue(app.images["wide landscape screenshot"].waitForExistence(timeout: 10))
        filter.tap()
        let payments = app.buttons["payments (2)"]
        XCTAssertTrue(payments.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(payments.isHittable)
        XCTAssertTrue(app.buttons["hiboss (6)"].exists)
        captureDemoScreenshot(app, name: "progress-project-menu-dark", test: self)
        payments.tap()
        XCTAssertTrue(app.images["retry latency chart"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.images["wide landscape screenshot"].waitForNonExistence(timeout: 5))
        filter.tap()
        XCTAssertTrue(app.buttons["payments (2)"].isSelected)
        captureDemoScreenshot(app, name: "progress-project-menu-selected-dark", test: self)
        app.buttons["All projects"].tap()
        XCTAssertTrue(app.images["wide landscape screenshot"].waitForExistence(timeout: 5))
        filter.tap()
        XCTAssertTrue(app.buttons["All projects"].isSelected)
    }
}
