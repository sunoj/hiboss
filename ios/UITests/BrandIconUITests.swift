// End-to-end coverage for the brand artwork shown during onboarding.
// Exports: BrandIconUITests, preventing the placeholder lettermark from returning.
// Dependencies: XCTest and the onboarding preview launch environment.

import XCTest

final class BrandIconUITests: XCTestCase {
    func testOnboardingUsesTheMacStyleBrandIcon() {
        let app = XCUIApplication()
        app.launchEnvironment["HIBOSS_DEMO_ONBOARDING"] = "1"
        app.launch()

        XCTAssertTrue(app.images["hiboss-brand-icon"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["h"].exists)
    }

    func testScannedPairingCodePrefillsServerURLBeforeRedemption() {
        let app = XCUIApplication()
        app.launchEnvironment["HIBOSS_DEMO_ONBOARDING"] = "1"
        app.launchEnvironment["HIBOSS_DEMO_PAIRING_SCAN"] = Self.pairingPayload
        app.launch()

        let serverField = app.textFields["server-url-field"]
        XCTAssertTrue(serverField.waitForExistence(timeout: 5))
        XCTAssertEqual(serverField.value as? String, "https://hiboss.example")
    }

    private static let pairingPayload =
        "hiboss://pair?server=https%3A%2F%2Fhiboss.example&code=hb_pair_" +
        String(repeating: "a", count: 64)
}
