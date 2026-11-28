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
        XCTAssertTrue(filter.appears(timeout: 10))
        XCTAssertTrue(app.images["wide landscape screenshot"].appears(timeout: 10))
        filter.tap()
        let payments = app.buttons["payments (2)"]
        XCTAssertTrue(payments.appears(timeout: 5), app.debugDescription)
        XCTAssertTrue(payments.isHittable)
        XCTAssertTrue(app.buttons["storefront (6)"].exists)
        captureDemoScreenshot(app, name: "progress-project-menu-dark", test: self)
        payments.tap()
        XCTAssertTrue(app.images["retry latency chart"].appears(timeout: 5))
        XCTAssertTrue(app.images["wide landscape screenshot"].disappears(timeout: 5))
        filter.tap()
        XCTAssertTrue(app.buttons["payments (2)"].isSelected)
        captureDemoScreenshot(app, name: "progress-project-menu-selected-dark", test: self)
        app.buttons["All projects"].tap()
        XCTAssertTrue(app.images["wide landscape screenshot"].appears(timeout: 5))
        filter.tap()
        XCTAssertTrue(app.buttons["All projects"].isSelected)
    }

    func testTagFiltersTheTimelineAndAllTagsRestoresPosts() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.configureDemoLaunch(["HIBOSS_TAB": "progress"])
        app.launchArguments = ["-AppleLanguages", "(en)"]
        app.launchConfiguredDemo()
        let first = app.images["wide landscape screenshot"].firstMatch
        XCTAssertTrue(first.appears(timeout: 10))
        let today = app.staticTexts["Today"].firstMatch
        let yesterday = app.staticTexts["Yesterday"].firstMatch
        XCTAssertTrue(today.exists)
        XCTAssertTrue(yesterday.exists)
        XCTAssertLessThan(today.frame.maxY, first.frame.minY)
        XCTAssertGreaterThan(yesterday.frame.minY, first.frame.maxY)
        let filter = app.buttons["Filter by project"]
        filter.tap()
        app.buttons["#hotfix"].tap()
        XCTAssertTrue(app.images["retry latency chart"].appears(timeout: 5))
        XCTAssertFalse(first.exists)
        filter.tap()
        XCTAssertTrue(app.buttons["#hotfix"].isSelected)
        app.buttons["All tags"].tap()
        XCTAssertTrue(first.appears(timeout: 5))
    }
}
