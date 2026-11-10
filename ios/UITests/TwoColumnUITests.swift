// Two-column Today and Sessions on a wide window (iPad mini landscape), with rotation and deep links.
// Exports: TwoColumnUITests, attaching "two-column-<appearance>-today|sessions" screenshots.
// Dependencies: XCTest and DemoLaunchSupport.

import XCTest

@MainActor
final class TwoColumnUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "two columns need a wide window")
        XCUIDevice.shared.orientation = .landscapeLeft
        app = XCUIApplication()
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    private func launch(_ extra: [String: String] = [:], appearance: String = "Light") {
        app.configureDemoLaunch(extra)
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                                "-AppleInterfaceStyle", appearance]
        app.launchConfiguredDemo()
    }

    /// An iPad shows its tabs at the top, outside a tab bar element.
    private var sessionsTab: XCUIElement { app.buttons["Sessions"].firstMatch }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    func testTodayShowsTheSelectedDecisionBesideTheCardsAcrossRotation() {
        launch()
        XCTAssertTrue(element("today-detail-placeholder").waitForExistence(timeout: 10))
        let card = app.buttons["home-message-c5"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        let question = app.staticTexts["message-question"]
        XCTAssertTrue(question.waitForExistence(timeout: 5), "the decision opens in the detail column")
        XCTAssertFalse(element("today-detail-placeholder").exists)
        XCTAssertTrue(card.isHittable, "the cards stay beside the detail, not under a sheet")

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5), "one column shows it in its sheet")
        XCTAssertTrue(question.exists, "rotating keeps the selected decision")

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(element("today-detail-placeholder").waitForNonExistence(timeout: 5))
        XCTAssertTrue(question.waitForExistence(timeout: 5), "rotating back keeps it in the column")
        XCTAssertTrue(card.isHittable)
    }

    func testSessionsShowTheSelectedFeedBesideTheList() {
        launch()
        sessionsTab.tap()
        XCTAssertTrue(element("sessions-detail-placeholder").waitForExistence(timeout: 10))
        let deploy = app.buttons["activity-session-sess-deploy"]
        let payments = app.buttons["activity-session-sess-pay"]
        XCTAssertTrue(deploy.waitForExistence(timeout: 5))
        deploy.tap()
        XCTAssertTrue(app.navigationBars["prod-release"].waitForExistence(timeout: 5))
        XCTAssertTrue(deploy.isSelected, "the list marks the session on the right")
        XCTAssertTrue(payments.isHittable, "the list stays beside the feed")
        XCTAssertTrue(app.buttons["Today"].firstMatch.isHittable, "the tabs stay reachable")
        payments.tap()
        XCTAssertTrue(app.navigationBars["payments-hotfix"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["prod-release"].exists, "a new selection replaces the feed")
    }

    func testSessionDeepLinkLandsInTheDetailColumnAndSurvivesRotation() {
        launch(["HIBOSS_DEMO_SESSION": "1"])
        XCTAssertTrue(app.navigationBars["prod-release"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["activity-session-sess-deploy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["activity-session-sess-deploy"].isSelected)

        XCUIDevice.shared.orientation = .portrait
        let back = app.navigationBars["prod-release"].buttons["Sessions"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "one column pushes the same feed")
        let row = app.buttons["activity-session-sess-deploy"]
        XCTAssertFalse(row.exists && row.isHittable, "the list is behind the pushed feed")
    }

    /// The screen, not the app: an app screenshot in landscape comes back turned and cropped.
    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCaptureTwoColumnScreens() {
        for appearance in ["Light", "Dark"] {
            launch(appearance: appearance)
            let card = app.buttons["home-message-c5"]
            XCTAssertTrue(card.waitForExistence(timeout: 10))
            card.tap()
            XCTAssertTrue(app.staticTexts["message-question"].waitForExistence(timeout: 5))
            shot("two-column-\(appearance)-today")
            sessionsTab.tap()
            app.buttons["activity-session-sess-deploy"].tap()
            XCTAssertTrue(app.navigationBars["prod-release"].waitForExistence(timeout: 5))
            shot("two-column-\(appearance)-sessions")
            app.terminate()
        }
    }
}
