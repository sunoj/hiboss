// End-to-end Today v4 shell, Settings sheet, results, and appearance evidence.
// Exports TodayV4UITests with retained screenshots of every changed surface.
// Dependencies: XCTest and launchConfiguredDemo; appearance is forced per launch.

import XCTest

@MainActor
final class TodayV4UITests: XCTestCase {
    func testLightScreens() { captureSurfaces(appearance: "Light") }
    func testDarkScreens() { captureSurfaces(appearance: "Dark") }

    func testCompactAllClearInLightAppearance() { captureCompactAllClear("Light") }
    func testCompactAllClearInDarkAppearance() { captureCompactAllClear("Dark") }

    func testRefreshKeepsCompactAllClearAndShowsOnlySmallStatus() {
        let app = launch("Light", extra: ["HIBOSS_DEMO_EMPTY": "1", "HIBOSS_DEMO_REFRESH_DELAY_MS": "60000"])
        let status = app.descendants(matching: .any).matching(identifier: "today-all-clear").firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let originalHeight = status.frame.height
        let started = Date()
        expectation(for: NSPredicate { _, _ in Date().timeIntervalSince(started) >= 6 }, evaluatedWith: app)
        waitForExpectations(timeout: 8)
        pullToRefresh(app)
        XCTAssertTrue(app.staticTexts["Refreshing…"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(status.exists, "A refresh must retain the verified idle layout")
        if status.exists { XCTAssertEqual(status.frame.height, originalHeight, accuracy: 1) }
        XCTAssertFalse(app.staticTexts["Checking coverage"].exists)
        let coverage = app.descendants(matching: .any).matching(identifier: "home-connection-status").firstMatch
        XCTAssertFalse(coverage.exists)
        shot(app, "Light-compact-refresh")
        app.terminate()
    }

    private func captureCompactAllClear(_ appearance: String) {
        let app = launch(appearance, extra: ["HIBOSS_DEMO_EMPTY": "1"])
        let status = app.descendants(matching: .any).matching(identifier: "today-all-clear").firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(status.isHittable)
        XCTAssertLessThanOrEqual(status.frame.height, 120, "All-clear must leave room for the workspace")
        XCTAssertFalse(app.staticTexts["Checking coverage"].exists)
        shot(app, "\(appearance)-compact-all-clear")
        app.terminate()
    }

    private func launch(_ appearance: String, extra: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.configureDemoLaunch(extra)
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-AppleInterfaceStyle", appearance]
        app.launchConfiguredDemo()
        return app
    }

    private func captureSurfaces(appearance: String) {
        continueAfterFailure = false
        let app = launch(appearance, extra: ["HIBOSS_DEMO_OPTION_MEDIA": "1"])
        XCTAssertTrue(app.buttons["home-message-c5"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.tabBars.buttons.allElementsBoundByIndex.map { $0.label },
                       ["Today", "Sessions", "Box", "Progress"])
        shot(app, "\(appearance)-today")
        app.buttons["today-settings"].tap()
        XCTAssertTrue(app.buttons["settings-connection"].waitForExistence(timeout: 5))
        shot(app, "\(appearance)-settings")
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["home-message-c5"].isHittable)
        app.buttons["home-message-c5"].tap()
        XCTAssertTrue(app.staticTexts["message-question"].waitForExistence(timeout: 5))
        shot(app, "\(appearance)-decision")
        app.navigationBars.buttons["Done"].tap()
        app.tabBars.buttons["Sessions"].tap()
        XCTAssertTrue(app.buttons["activity-session-sess-deploy"].waitForExistence(timeout: 5))
        shot(app, "\(appearance)-sessions")
        app.buttons["activity-session-sess-deploy"].tap()
        XCTAssertTrue(app.navigationBars["prod-release"].waitForExistence(timeout: 5))
        shot(app, "\(appearance)-session-thread")
        app.tabBars.buttons["Box"].tap()
        XCTAssertTrue(app.buttons["box-item-demo-text"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Box"].exists)
        shot(app, "\(appearance)-box")
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 5))
        shot(app, "\(appearance)-progress")
        app.terminate()
        captureTodayStates(appearance)
    }

    private func captureTodayStates(_ appearance: String) {
        var app = launch(appearance, extra: ["HIBOSS_DEMO_EMPTY": "1"])
        XCTAssertTrue(app.staticTexts["Nothing needs you"].waitForExistence(timeout: 10))
        shot(app, "\(appearance)-all-clear")
        app.terminate()
        app = launch(appearance, extra: ["HIBOSS_DEMO_ATTACHMENTS": "1"])
        let delivered = app.staticTexts["Delivered"]
        for _ in 0..<8 where !delivered.isHittable { app.swipeUp() }
        XCTAssertTrue(delivered.waitForExistence(timeout: 10))
        XCTAssertTrue(app.images["message-attachment-image"].firstMatch.exists)
        let filename = app.staticTexts["today-delivered-filename"]
        // The row sits below the heading; scroll it clear of the floating tab bar.
        for _ in 0..<4 where !filename.isHittable { app.swipeUp() }
        XCTAssertTrue(filename.isHittable)
        XCTAssertGreaterThan(filename.frame.width, 100, "filenames belong beside the thumbnail")
        XCTAssertLessThan(filename.frame.height, 44, "the filename must remain readable")
        XCTAssertTrue(app.staticTexts["prod-release · worker-design"].exists)
        shot(app, "\(appearance)-delivered")
        app.terminate()
        app = launch(appearance, extra: ["HIBOSS_DEMO_EMPTY": "1", "HIBOSS_PANELS_DEMO": "1"])
        let watching = app.staticTexts["Watching"]
        for _ in 0..<8 where !watching.isHittable { app.swipeUp() }
        XCTAssertTrue(watching.waitForExistence(timeout: 10))
        shot(app, "\(appearance)-watching")
        app.terminate()
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "v4-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
