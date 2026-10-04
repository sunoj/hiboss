// Settings > Sign in a Mac in demo mode: a scanned request is reviewed, approved and its code shown;
// a code for another server is refused. HIBOSS_DEMO_SIGNIN_SCAN stands in for the camera.
// Exports: MacSigninUITests. Dependencies: XCTest, DemoLaunchSupport.

import XCTest

final class MacSigninUITests: XCTestCase {
    private var app: XCUIApplication!
    private let requestID = String(repeating: "ab", count: 16)

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(scanning server: String) {
        let link = "hiboss://signin?server=\(server)&request=\(requestID)"
        app.configureDemoLaunch(["HIBOSS_DEMO_SIGNIN_SCAN": link])
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let row = app.buttons["Sign in a Mac"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
    }

    func testApprovedRequestShowsTheCodeUntilDone() {
        launch(scanning: "https%3A%2F%2Fhiboss.example.com")
        // LabeledContent reads as one element: "Calls itself, Studio MacBook Pro".
        XCTAssertTrue(app.staticTexts["Calls itself, Studio MacBook Pro"].waitForExistence(timeout: 5), "the review names the Mac")
        XCTAssertTrue(app.staticTexts["Location, NL · Amsterdam"].exists, "the review shows where the request came from")
        app.buttons["mac-signin.approve"].tap()

        let code = app.staticTexts["mac-signin.code"]
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        XCTAssertEqual(code.label, "Sign-in code 3 0 6 1 4 2", "VoiceOver reads the digits one by one")
        XCTAssertTrue(app.staticTexts["Type this code on your Mac"].exists)
        XCTAssertTrue(app.staticTexts["A Mac calling itself “Studio MacBook Pro”"].exists, "the label is quoted as a claim")
        let warning = app.descendants(matching: .any)["mac-signin.warning"]
        XCTAssertTrue(warning.exists)
        XCTAssertTrue(warning.label.contains("Never read it out or send it to anyone"), warning.label)
        XCTAssertFalse(app.navigationBars.buttons["Settings"].exists, "Back would drop the code; only Done leaves")

        app.buttons["mac-signin.done"].tap()
        XCTAssertTrue(app.buttons["Sign in a Mac"].waitForExistence(timeout: 5), "Done returns to Settings")
    }

    func testCodeForAnotherServerIsRefused() {
        launch(scanning: "https%3A%2F%2Fother.example")
        let rejection = app.staticTexts["This Mac is signing in to a different server: other.example"]
        XCTAssertTrue(rejection.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["mac-signin.approve"].exists)
    }
}
