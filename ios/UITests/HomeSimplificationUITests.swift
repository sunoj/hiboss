// Verifies Today decisions retain context, timeout authority, and reachable native answers.
// Exports: HomeSimplificationUITests with matched English and Chinese Home screenshots.
// Dependencies: XCTest, DemoLaunchSupport; baseline heights from the iPhone 17 main screenshot.

import XCTest

final class HomeSimplificationUITests: XCTestCase {
    func testEmptyHomeRetainsReadableAllClear() {
        let app = XCUIApplication()
        app.configureDemoLaunch(["HIBOSS_DEMO_EMPTY": "1"])
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchConfiguredDemo()
        let message = app.staticTexts["没有需要你处理的事"]
        XCTAssertTrue(message.waitForExistence(timeout: 10))
        XCTAssertTrue(message.isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = (ProcessInfo.processInfo.environment["UX_TOUR_PREFIX"] ?? "") + "zh-empty-home"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testRequestsRemainAnswerableWithContextAndTimeoutAuthority() {
        for language in ["en", "zh-Hans"] {
            let app = XCUIApplication()
            app.configureDemoLaunch()
            app.launchArguments = [
                "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN",
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
            ]
            app.launchConfiguredDemo()
            let first = app.buttons["home-message-c5"]
            XCTAssertTrue(first.waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["Coarse grid"].isHittable)
            XCTAssertTrue(app.buttons["Fine grid"].isHittable)
            let timing = app.descendants(matching: .any)["decision-timing-c5"].firstMatch
            XCTAssertTrue(timing.label.contains(language == "en" ? "That is not approval" : "这不代表批准"))
            for _ in 0..<8 where !app.buttons["Reject"].isHittable { app.swipeUp() }
            XCTAssertTrue(app.buttons["Approve"].isHittable)
            XCTAssertTrue(app.buttons["Reject"].isHittable)
            for option in ["Approve", "Reject"] {
                XCTAssertGreaterThanOrEqual(app.buttons[option].frame.height, 44)
            }
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "\(language)-today-decisions"
            shot.lifetime = .keepAlways
            add(shot)
            app.terminate()
        }
    }
}
