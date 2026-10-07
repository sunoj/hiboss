// Settings navigation, draft retention, delayed recovery and security review from notification links.
// Exports: SettingsNavigationUITests; all launches use launchConfiguredDemo().
// Dependencies: XCTest, DemoLaunchSupport, Settings-only demo operation hooks.

import XCTest

final class SettingsNavigationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ extra: [String: String] = [:]) {
        app.configureDemoLaunch(extra)
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchConfiguredDemo()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 8))
        app.tabBars.buttons["Settings"].tap()
    }

    private func openDevices(_ name: String) {
        app.buttons["settings-devices"].tap()
        app.buttons[name].tap()
    }

    private func toggle(_ control: XCUIElement) {
        let previous = control.value as? String
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertNotEqual(control.value as? String, previous, "the switch must change before saving")
    }

    func testRootHasFiveRowsAndSignOutWithinReach() {
        launch()
        XCTAssertEqual(app.cells.count, 5)
        XCTAssertTrue(app.buttons["settings-sign-out"].isHittable)
        XCTAssertFalse(app.buttons["Pair another device"].exists)
        app.buttons["settings-connection"].tap()
        XCTAssertTrue(app.staticTexts["This phone is connected to your server."].waitForExistence(timeout: 5))
    }

    func testFailedSaveKeepsInputAndNavigationKeepsTheDraft() {
        launch(["HIBOSS_DEMO_PREFERENCES_FAIL": "1"])
        app.buttons["settings-notifications"].tap()
        let mute = app.switches["settings-quiet-hours"]
        XCTAssertTrue(mute.waitForExistence(timeout: 5))
        for _ in 0..<3 where !mute.isHittable { app.swipeUp() }
        toggle(mute)
        XCTAssertTrue(app.buttons["settings-preferences-save"].waitForExistence(timeout: 5))
        app.buttons["settings-preferences-save"].tap()
        let retry = app.buttons["settings-preferences-retry"]
        for _ in 0..<4 where !retry.isHittable { app.swipeUp() }
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        shot("en-state-save-failed")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["settings-notifications"].tap()
        XCTAssertEqual(app.switches["settings-quiet-hours"].value as? String, "0")
        XCTAssertTrue(app.buttons["settings-preferences-save"].isEnabled)
    }

    func testLongSaveDisablesOnlySaveAndAllowsAnotherEdit() {
        launch(["HIBOSS_DEMO_PREFERENCES_DELAY_MS": "12000"])
        app.buttons["settings-notifications"].tap()
        let mute = app.switches["settings-quiet-hours"]
        XCTAssertTrue(mute.waitForExistence(timeout: 5))
        for _ in 0..<3 where !mute.isHittable { app.swipeUp() }
        toggle(mute)
        XCTAssertTrue(app.buttons["settings-preferences-save"].waitForExistence(timeout: 5))
        app.buttons["settings-preferences-save"].tap()
        XCTAssertFalse(app.buttons["settings-preferences-save"].isEnabled)
        XCTAssertTrue(mute.isEnabled)
        toggle(mute)
        let wait = app.staticTexts["Taking longer than usual. Check your connection."]
        for _ in 0..<3 where !wait.exists { app.swipeUp() }
        XCTAssertTrue(wait.waitForExistence(timeout: 12))
        shot("en-state-save-long")
        XCTAssertTrue(app.buttons["settings-preferences-save"].waitForExistence(timeout: 8))
        let enabled = NSPredicate(format: "enabled == true")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: enabled,
            evaluatedWith: app.buttons["settings-preferences-save"])], timeout: 8), .completed)
    }

    func testPairingLongWaitExplainsAndOffersClose() {
        launch(["HIBOSS_DEMO_SETTINGS_DELAY_MS": "16000", "HIBOSS_DEMO_SETTINGS_DELAY_OPERATION": "pairing"])
        openDevices("Pair another device")
        XCTAssertTrue(app.staticTexts["Requesting a pairing code…"].waitForExistence(timeout: 5))
        let longWait = app.staticTexts["Taking longer than usual. Check your connection."]
        XCTAssertTrue(longWait.waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons["Close"].isEnabled)
        shot("en-state-pair-long")
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Sign in a Mac"].waitForExistence(timeout: 5))
    }

    func testPairingPermissionDenialKeepsItsExactRoleMessage() {
        launch(["HIBOSS_DEMO_SETTINGS_FAILURE": "pairing-denied"])
        openDevices("Pair another device")
        XCTAssertTrue(app.staticTexts["Your role cannot pair devices"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Copy Link"].exists)
        shot("en-state-pair-denied")
    }

    func testPushedJoinRequestStillOpensItsVerificationReview() {
        app.configureDemoLaunch(["HIBOSS_DEMO_JOIN_REQUEST": "jr-build"])
        app.launchConfiguredDemo()
        XCTAssertTrue(app.staticTexts["join-request.code"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Name, build-box-2"].exists)
        XCTAssertTrue(app.staticTexts["Host, build-box-2.local"].exists)
        XCTAssertTrue(app.buttons["join-request.approve"].isEnabled)
        app.buttons["join-request.approve"].tap()
        XCTAssertTrue(app.staticTexts["build-box-2 can now join"].waitForExistence(timeout: 5))
    }

    func testFailedApprovalKeepsTheCodeAndCloseEnabled() {
        launch(["HIBOSS_DEMO_SETTINGS_FAILURE": "approval"])
        openDevices("Device Requests")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'build-box-2'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["join-request.code"].waitForExistence(timeout: 5))
        app.buttons["join-request.approve"].tap()
        XCTAssertTrue(app.staticTexts["join-request.code"].exists)
        XCTAssertTrue(app.buttons["Close"].isEnabled)
        XCTAssertTrue(app.buttons["join-request.approve"].isEnabled)
        shot("en-state-approval-failed")
    }

    func testDeviceRequestLoadFailureOffersRetry() {
        launch(["HIBOSS_DEMO_SETTINGS_FAILURE": "requests"])
        openDevices("Device Requests")
        XCTAssertTrue(app.staticTexts["Device requests unavailable"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Try again"].isEnabled)
        shot("en-state-requests-failed")
    }

    func testEmptyDeviceRequestsExplainWhatWillAppear() {
        launch(["HIBOSS_DEMO_REQUESTS_EMPTY": "1"])
        openDevices("Device Requests")
        XCTAssertTrue(app.staticTexts["No device requests"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["New machines appear here when they ask to join."].exists)
        shot("en-state-requests-empty")
    }

    func testApprovalInFlightKeepsTheCodeAndCloseUsable() {
        launch(["HIBOSS_DEMO_SETTINGS_DELAY_MS": "12000", "HIBOSS_DEMO_SETTINGS_DELAY_OPERATION": "approval"])
        openDevices("Device Requests")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'build-box-2'")).firstMatch.tap()
        app.buttons["join-request.approve"].tap()
        XCTAssertFalse(app.buttons["join-request.approve"].isEnabled)
        XCTAssertTrue(app.staticTexts["join-request.code"].exists)
        XCTAssertTrue(app.buttons["Close"].isEnabled)
        shot("en-state-approval-pending")
    }

    func testFailedMacApprovalKeepsTheScannedIdentity() {
        let request = String(repeating: "ab", count: 16)
        launch([
            "HIBOSS_DEMO_SETTINGS_FAILURE": "signin-approval",
            "HIBOSS_DEMO_SIGNIN_SCAN":
                "hiboss://signin?server=https%3A%2F%2Fhiboss.example.com&request=\(request)",
        ])
        openDevices("Sign in a Mac")
        XCTAssertTrue(app.buttons["mac-signin.approve"].waitForExistence(timeout: 5))
        app.buttons["mac-signin.approve"].tap()
        XCTAssertTrue(app.buttons["mac-signin.scan-again"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Calls itself, Studio MacBook Pro"].exists)
        XCTAssertTrue(app.staticTexts["Location, NL · Amsterdam"].exists)
        shot("en-state-mac-approval-failed")
    }

    func testPriorityDeliveryCanBeChangedAndSavedFromDetails() {
        launch()
        app.buttons["settings-notifications"].tap()
        let details = app.buttons["settings-delivery"]
        for _ in 0..<5 where !details.isHittable { app.swipeUp() }
        details.tap()
        app.buttons["settings-push-critical"].tap()
        XCTAssertTrue(app.buttons["Off"].waitForExistence(timeout: 5))
        app.buttons["Off"].tap()
        XCTAssertTrue(app.buttons["settings-preferences-save"].waitForExistence(timeout: 5))
        app.buttons["settings-preferences-save"].tap()
        XCTAssertTrue(app.buttons["settings-preferences-save"].waitForNonExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.swipeDown()
        app.swipeDown()
        let summary = app.staticTexts["Phone alerts, High and Normal"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
