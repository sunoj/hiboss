// First run without the demo launch flag: entering and exiting the demo, typed pairing codes.
// Exports: FirstRunUITests. Assumes a simulator with no saved HiBoss account.
// Dependencies: XCTest and DemoLaunchSupport.

import XCTest

@MainActor
final class FirstRunUITests: XCTestCase {
    private lazy var app: XCUIApplication = {
        let app = XCUIApplication()
        for key in ["HIBOSS_DEMO", "HIBOSS_DEMO_ONBOARDING", "HIBOSS_DEMO_PAIRING_SCAN"] {
            app.launchEnvironment[key] = ""
        }
        return app
    }()

    func testExploreDemoThenExitLeavesAConnectScreenWithNoDemoContent() {
        launchSignedOut()
        app.buttons["connect-explore-demo"].tap()

        let exit = app.buttons["demo-exit"]
        XCTAssertTrue(exit.waitForExistence(timeout: 10), "The demo shows Exit on every screen")
        XCTAssertTrue(app.buttons["today-working-sess-deploy"].waitForExistence(timeout: 10))
        app.tabBars.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(exit.isHittable)
        captureDemoScreenshot(app, name: "first-run-demo-sessions", test: self)

        exit.tap()
        XCTAssertTrue(app.textFields["server-url-field"].waitForExistence(timeout: 10))
        assertNoDemoContent()

        app.terminate()
        app.launch()
        XCTAssertTrue(app.textFields["server-url-field"].waitForExistence(timeout: 10))
        assertNoDemoContent()
    }

    func testDemoLastsAcrossRelaunchUntilExit() {
        launchSignedOut()
        app.buttons["connect-explore-demo"].tap()
        XCTAssertTrue(app.buttons["demo-exit"].waitForExistence(timeout: 10))

        app.terminate()
        app.launch()
        let exit = app.buttons["demo-exit"]
        XCTAssertTrue(exit.waitForExistence(timeout: 10))
        exit.tap()
        XCTAssertTrue(app.textFields["server-url-field"].waitForExistence(timeout: 10))
    }

    func testTypedPairingCodeIsValidatedBeforeAnyRequest() {
        launchSignedOut()
        app.buttons["connect-enter-code"].tap()
        let server = app.textFields["pairing-server-field"]
        XCTAssertTrue(server.waitForExistence(timeout: 5))
        server.tap()
        server.typeText("http://hiboss.example.com")
        let code = app.textFields["pairing-code-field"]
        code.tap()
        code.typeText("hb_pair_" + String(repeating: "a", count: 64))
        app.buttons["pairing-code-submit"].tap()

        let footer = app.staticTexts["pairing-code-footer"]
        XCTAssertTrue(footer.waitForExistence(timeout: 5))
        XCTAssertTrue(footer.label.contains("HTTPS"), footer.label)
    }

    func testTappedPairLinkOpensThePrefilledCodeSheet() throws {
        launchSignedOut()
        let link = "hiboss://pair?server=https%3A%2F%2Fhiboss.example.com&code=hb_pair_"
            + String(repeating: "b", count: 64)
        app.open(try XCTUnwrap(URL(string: link)))

        let server = app.textFields["pairing-server-field"]
        XCTAssertTrue(server.waitForExistence(timeout: 10))
        XCTAssertEqual(server.value as? String, "https://hiboss.example.com")
        XCTAssertTrue(app.buttons["pairing-code-submit"].isEnabled)
    }

    func testPairLinkTappedDuringTheDemoOpensThePrefilledSheetAfterExit() throws {
        launchSignedOut()
        app.buttons["connect-explore-demo"].tap()
        let exit = app.buttons["demo-exit"]
        XCTAssertTrue(exit.waitForExistence(timeout: 10))
        let link = "hiboss://pair?server=https%3A%2F%2Fhiboss.example.com&code=hb_pair_"
            + String(repeating: "c", count: 64)
        app.open(try XCTUnwrap(URL(string: link)))
        XCTAssertTrue(exit.waitForExistence(timeout: 10), "The demo keeps running until Exit")

        exit.tap()
        let server = app.textFields["pairing-server-field"]
        XCTAssertTrue(server.waitForExistence(timeout: 10), "The held link opens after Exit")
        XCTAssertEqual(server.value as? String, "https://hiboss.example.com")
    }

    func testPlainHTTPPairLinkShowsTheHTTPSMessage() throws {
        launchSignedOut()
        let link = "hiboss://pair?server=http%3A%2F%2Fhiboss.example.com&code=hb_pair_"
            + String(repeating: "d", count: 64)
        app.open(try XCTUnwrap(URL(string: link)))

        let message = app.staticTexts["connect-error"]
        XCTAssertTrue(message.waitForExistence(timeout: 10))
        XCTAssertTrue(message.label.contains("HTTPS"), message.label)
        XCTAssertFalse(app.textFields["pairing-server-field"].exists)
    }

    /// Ends a demo a failed earlier run may have left, so every test starts signed out.
    private func launchSignedOut() {
        continueAfterFailure = false
        app.launchConfiguredDemo()
        if app.buttons["demo-exit"].waitForExistence(timeout: 3) { app.buttons["demo-exit"].tap() }
        XCTAssertTrue(app.textFields["server-url-field"].waitForExistence(timeout: 10),
                      "This test needs a simulator without a saved HiBoss account")
        XCTAssertTrue(app.buttons["connect-explore-demo"].waitForExistence(timeout: 5))
    }

    private func assertNoDemoContent() {
        XCTAssertFalse(app.buttons["demo-exit"].exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        XCTAssertFalse(app.buttons["today-settings"].exists)
        XCTAssertFalse(app.buttons["today-working-sess-deploy"].exists)
    }
}
