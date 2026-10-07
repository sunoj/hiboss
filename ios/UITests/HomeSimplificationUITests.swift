// Verifies two complete Home requests fit above the tab bar at default text size.
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

    func testFirstTwoRequestsFitWithoutGrowingBeyondMain() {
        for language in ["en", "zh-Hans"] {
            let app = XCUIApplication()
            app.configureDemoLaunch()
            app.launchArguments = [
                "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN",
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
            ]
            app.launchConfiguredDemo()
            let first = app.buttons["home-message-c5"]
            let second = app.buttons["home-message-c1"]
            XCTAssertTrue(first.waitForExistence(timeout: 10))
            XCTAssertTrue(second.exists)
            let firstBottom = app.buttons["Coarse grid"].frame.maxY + 12
            let secondBottom = app.buttons["Reject"].frame.maxY + 12
            XCTAssertLessThanOrEqual(firstBottom, app.tabBars.firstMatch.frame.minY)
            XCTAssertLessThanOrEqual(secondBottom, app.tabBars.firstMatch.frame.minY)
            XCTAssertLessThanOrEqual(firstBottom - first.frame.minY + 12, 268)
            XCTAssertLessThanOrEqual(secondBottom - second.frame.minY + 12, 268)
            for option in ["Coarse grid", "Fine grid", "Approve", "Reject"] {
                XCTAssertTrue(app.buttons[option].isHittable)
                XCTAssertGreaterThanOrEqual(app.buttons[option].frame.height, 44)
            }
            let timing = app.descendants(matching: .any)["decision-timing-c5"].firstMatch
            XCTAssertLessThanOrEqual(timing.frame.height, 20, "default and countdown share one line")
            XCTContext.runActivity(named: "\(language): cards \(firstBottom - first.frame.minY + 12), "
                + "\(secondBottom - second.frame.minY + 12); bottom \(secondBottom); "
                + "tab bar \(app.tabBars.firstMatch.frame.minY)") { _ in }
            let shot = XCTAttachment(screenshot: app.screenshot())
            let prefix = ProcessInfo.processInfo.environment["UX_TOUR_PREFIX"] ?? ""
            shot.name = prefix + (language == "en" ? "en" : "zh") + "-01-home"
            shot.lifetime = .keepAlways
            add(shot)
            app.terminate()
        }
    }
}
