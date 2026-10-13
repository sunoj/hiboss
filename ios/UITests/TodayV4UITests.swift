// End-to-end Today v4 shell, Settings sheet, results, and appearance evidence.
// Exports TodayV4UITests with retained screenshots of every changed surface.
// Dependencies: XCTest and launchConfiguredDemo; appearance is forced per launch.

import XCTest

@MainActor
final class TodayV4UITests: XCTestCase {
    private var capturesLargeText = false
    func testSlowPanelsNeverCoverLoadedWorkingRows() {
        let app = launch("Light", extra: ["HIBOSS_DEMO_EMPTY": "1",
                                          "HIBOSS_DEMO_PANELS_DELAY_MS": "60000"])
        defer { app.terminate() }
        let row = app.buttons["today-working-sess-deploy"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let waiting = app.descendants(matching: .any)
            .matching(identifier: "home-connection-status").firstMatch
        XCTAssertTrue(waiting.waitForExistence(timeout: 5))
        for id in ["sess-deploy", "direct", "sess-payments"] {
            let loaded = app.buttons["today-working-\(id)"].firstMatch
            if loaded.exists {
                XCTAssertFalse(waiting.frame.intersects(loaded.frame), "The wait must own layout space")
            }
        }
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "pending-rows").firstMatch.exists,
                       "Loaded sessions must never have skeletons over them")
        shot(app, "Light-slow-panels")
    }

    func testPanelCompletionKeepsLoadedWorkingRowsInPlace() {
        let app = launch("Light", extra: ["HIBOSS_DEMO_EMPTY": "1",
                                          "HIBOSS_DEMO_PANELS_DELAY_MS": "15000"])
        defer { app.terminate() }
        let row = app.buttons["today-working-sess-deploy"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Nothing needs you"].exists)
        let before = row.frame
        XCTAssertTrue(app.staticTexts["Nothing needs you"].waitForExistence(timeout: 20))
        XCTAssertEqual(row.frame.minY, before.minY, accuracy: 1)
        XCTAssertEqual(row.frame.height, before.height, accuracy: 1)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "pending-rows").firstMatch.exists)
    }

    func testLightScreens() { captureSurfaces(appearance: "Light") }
    func testDarkScreens() { captureSurfaces(appearance: "Dark") }
    func testRecordedTimeLightScreens() { captureRecordedScreens("Light") }
    func testRecordedTimeDarkScreens() { captureRecordedScreens("Dark") }
    func testRecordedTimeAccessibilityScreens() {
        capturesLargeText = true
        defer { capturesLargeText = false }
        captureRecordedScreens("Light")
    }

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
        if capturesLargeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName",
                                    "UICTContentSizeCategoryAccessibilityL"]
        }
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
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(app.tabBars.buttons["Box"].waitForExistence(timeout: 5))
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

    private func captureRecordedScreens(_ appearance: String) {
        continueAfterFailure = false
        var app = launch(appearance, extra: ["HIBOSS_DEMO_EMPTY": "1",
                                            "HIBOSS_DEMO_PANELS_DELAY_MS": "60000"])
        XCTAssertTrue(app.buttons["today-working-sess-deploy"].waitForExistence(timeout: 10))
        polishShot(app, "\(appearance)-today-loading")
        for _ in 0..<3 { app.swipeUp() }
        polishShot(app, "\(appearance)-today-pending")
        app.terminate()
        app = launch(appearance)
        app.tabBars.buttons["Sessions"].tap()
        XCTAssertTrue(app.buttons["activity-session-sess-deploy"].waitForExistence(timeout: 10))
        polishShot(app, "\(appearance)-sessions")
        app.buttons["activity-session-sess-deploy"].tap()
        XCTAssertTrue(app.buttons["Message history"].waitForExistence(timeout: 10))
        for _ in 0..<6 { app.swipeDown() }
        polishShot(app, "\(appearance)-session-facts")
        app.buttons["Message history"].tap()
        XCTAssertTrue(app.navigationBars["Messages"].waitForExistence(timeout: 5))
        polishShot(app, "\(appearance)-messages")
        app.terminate()
        captureRecordedPeers(appearance)
        app = launch(appearance, extra: ["HIBOSS_DEMO_OPEN": "c1"])
        XCTAssertTrue(app.staticTexts["message-question"].waitForExistence(timeout: 10))
        polishShot(app, "\(appearance)-decision")
        let more = app.buttons["message-more-information"]
        for _ in 0..<8 where !more.isHittable { app.swipeUp() }
        XCTAssertTrue(more.isHittable)
        more.tap()
        app.swipeUp()
        polishShot(app, "\(appearance)-decision-details")
        app.terminate()
        captureSecondaryRecordedScreens(appearance)
    }

    private func captureRecordedPeers(_ appearance: String) {
        let app = launch(appearance, extra: ["HIBOSS_DEMO_PEERS": "1", "HIBOSS_DEMO_SESSION": "1"])
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Message history"].waitForExistence(timeout: 10))
        for _ in 0..<6 { app.swipeDown() }
        let peers = app.descendants(matching: .any).matching(identifier: "project-peers").firstMatch
        XCTAssertTrue(peers.waitForExistence(timeout: 5))
        peers.tap()
        polishShot(app, "\(appearance)-session-peers")
    }

    private func captureSecondaryRecordedScreens(_ appearance: String) {
        var app = launch(appearance, extra: ["HIBOSS_DEMO_BOX_V2": "1"])
        app.tabBars.buttons["Box"].tap()
        XCTAssertTrue(app.buttons["box-item-demo-text"].waitForExistence(timeout: 10))
        polishShot(app, "\(appearance)-box")
        app.buttons["box-item-demo-text"].tap()
        XCTAssertTrue(app.scrollViews["box-detail"].waitForExistence(timeout: 5))
        polishShot(app, "\(appearance)-box-details")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["box-item-demo-image"].tap()
        XCTAssertTrue(app.buttons["media-viewer-close"].waitForExistence(timeout: 10))
        polishShot(app, "\(appearance)-box-media")
        app.buttons["media-viewer-close"].tap()
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 10))
        polishShot(app, "\(appearance)-progress")
        app.terminate()
        app = launch(appearance, extra: ["HIBOSS_DEMO_RESOLVED": "1"])
        XCTAssertTrue(app.navigationBars["Resolved"].waitForExistence(timeout: 10))
        polishShot(app, "\(appearance)-resolved")
        app.terminate()
        app = launch(appearance)
        XCTAssertTrue(app.buttons["today-settings"].waitForExistence(timeout: 10))
        app.buttons["today-settings"].tap()
        tapVisible(app, "settings-devices")
        tapVisible(app, "Device Requests")
        let request = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'build-box-2'"))
            .firstMatch
        XCTAssertTrue(request.waitForExistence(timeout: 10))
        polishShot(app, "\(appearance)-device-requests")
        request.tap()
        XCTAssertTrue(app.staticTexts["join-request.code"].waitForExistence(timeout: 5))
        polishShot(app, "\(appearance)-device-review")
        app.terminate()
    }

    private func polishShot(_ app: XCUIApplication, _ name: String) {
        shot(app, "polish-\(capturesLargeText ? "AX-" : "")\(name)")
        // Allow the host capture command to retain the same screen with simctl.
        let until = Date().addingTimeInterval(2)
        let hold = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in Date() >= until }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [hold], timeout: 3), .completed)
    }

    private func tapVisible(_ app: XCUIApplication, _ identifier: String) {
        let button = app.buttons[identifier].firstMatch
        for _ in 0..<8 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.isHittable)
        button.tap()
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "v4-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
