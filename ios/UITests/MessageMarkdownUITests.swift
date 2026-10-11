// Verifies separate short titles and readable Markdown details in the native message view.
// Uses demo notification navigation; screenshots retain light/dark and large-text evidence.

import XCTest

@MainActor
final class MessageMarkdownUITests: XCTestCase {
    func testMarkdownBodyRendersBelowTheShortTitleInBothAppearances() {
        for appearance in ["Light", "Dark"] {
            let app = launch(appearance: appearance)
            XCTAssertTrue(app.staticTexts["message-question"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.staticTexts["message-question"].label, "House update")
            XCTAssertTrue(app.staticTexts["Result"].exists)
            XCTAssertTrue(app.staticTexts["First item"].exists)
            XCTAssertTrue(app.staticTexts["Second item"].exists)
            XCTAssertTrue(app.staticTexts["Verified details"].exists)
            XCTAssertTrue(app.staticTexts["let ready = true"].exists)
            XCTAssertFalse(app.staticTexts["## Result"].exists)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "message-markdown-\(appearance)"
            shot.lifetime = .keepAlways
            add(shot)
            app.terminate()
        }
    }

    func testHistoricalLongTitleKeepsItsFullTextInTheBodyAtLargeText() {
        let app = launch(appearance: "Light", longTitle: true)
        XCTAssertTrue(app.staticTexts["message-question"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["message-question"].label.unicodeScalars.count, 144)
        let fullText = String(repeating: "Historical title ", count: 12)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", fullText)).firstMatch.exists)
        XCTAssertLessThanOrEqual(app.staticTexts["message-question"].frame.width, app.frame.width)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "message-markdown-historical-large"
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func launch(appearance: String, longTitle: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.configureDemoLaunch([
            "HIBOSS_DEMO_MARKDOWN": "1", "HIBOSS_DEMO_NOTIFICATION_OPEN": "markdown-report",
            "HIBOSS_DEMO_LONG_TITLE": longTitle ? "1" : "0",
        ])
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                                "-AppleInterfaceStyle", appearance]
        if longTitle {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName",
                                    "UICTContentSizeCategoryAccessibilityL"]
        }
        app.launchConfiguredDemo()
        return app
    }
}
