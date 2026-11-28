// Today's Watching summary pushes the full wall; a card there opens the panel detail.
// Exports TodayWatchingUITests. The detail sheet belongs to Today's root view, which stays
// under the pushed Watching screen, so this checks it still presents from there.
// Dependencies: XCTest and DemoLaunchSupport (configured demo launch, appears).

import XCTest

final class TodayWatchingUITests: XCTestCase {
    func testWatchingScreenOpensPanelDetail() {
        let app = XCUIApplication()
        app.configureDemoLaunch(["HIBOSS_DEMO_NATIVE_PANEL": "1"])
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchConfiguredDemo()
        let all = app.buttons["today-watching-all"].firstMatch
        XCTAssertTrue(all.appears(timeout: 10))
        for _ in 0..<8 where !all.isHittable { app.swipeUp() }
        all.tap()
        XCTAssertTrue(app.navigationBars["Watching"].appears(timeout: 5))
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Release checklist")).firstMatch
        XCTAssertTrue(card.appears(timeout: 10))
        card.tap()
        XCTAssertTrue(app.buttons["Done"].appears(timeout: 5), "the panel detail opens from Watching")
    }
}
