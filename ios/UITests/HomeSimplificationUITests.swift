// Verifies Today decisions retain context, timeout authority, and reachable native answers.
// Exports: HomeSimplificationUITests with matched English and Chinese Home screenshots.
// Dependencies: XCTest, DemoLaunchSupport; baseline heights from the iPhone 17 main screenshot.

import XCTest

@MainActor
final class HomeSimplificationUITests: XCTestCase {
    func testDisconnectedHomeOffersSettingsWithoutAnInertRetry() {
        let app = launchRecoveryState("disconnected")
        XCTAssertTrue(app.staticTexts["Not connected"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["home-connection-status"].label, "Not connected")
        XCTAssertFalse(app.staticTexts["Checking coverage"].exists)
        XCTAssertFalse(app.buttons["pending-retry"].exists)
        XCTAssertFalse(app.staticTexts["Nothing needs you"].exists)
        keepRecoveryScreenshot(app, "en-home-disconnected")
        let settings = recoverySettings(app)
        XCTAssertTrue(settings.isHittable)
        XCTAssertGreaterThanOrEqual(settings.frame.height, 44)
        settings.tap()
        XCTAssertTrue(app.buttons["settings-connection"].waitForExistence(timeout: 5))
    }

    func testFailedHomeNamesTheCauseAndKeepsLoadedResultsAboveTheFold() {
        let app = launchRecoveryState("failed")
        XCTAssertTrue(app.staticTexts["Not connected"].waitForExistence(timeout: 5))
        let status = app.staticTexts["home-connection-status"]
        XCTAssertTrue(status.label.contains("Couldn't reach the server."))
        XCTAssertFalse(app.staticTexts["Checking coverage"].exists)
        XCTAssertFalse(app.staticTexts["Nothing needs you"].exists)
        let retry = app.buttons["pending-retry"]
        XCTAssertTrue(retry.isHittable)
        XCTAssertGreaterThanOrEqual(retry.frame.height, 44)
        let delivered = app.staticTexts["Delivered"]
        XCTAssertTrue(delivered.waitForExistence(timeout: 5))
        XCTAssertTrue(delivered.isHittable,
                      "a terminal error must not displace real results with placeholders")
        XCTAssertLessThan(delivered.frame.maxY, app.tabBars.firstMatch.frame.minY)
        keepRecoveryScreenshot(app, "en-home-failed")
    }

    func testConnectingHomeNamesTheConnectionWait() {
        let app = launchRecoveryState("connecting")
        XCTAssertTrue(app.staticTexts["Connecting…"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Checking coverage"].exists)
        XCTAssertFalse(app.staticTexts["Nothing needs you"].exists)
        keepRecoveryScreenshot(app, "en-home-connecting")
    }

    func testRecoveryRemainsReachableAtLargeTextInBothLanguagesAndAppearances() {
        for language in ["en", "zh-Hans"] {
            for appearance in ["Light", "Dark"] {
                let app = launchRecoveryState("failed", language: language, appearance: appearance,
                                              largeText: true)
                let chinese = language == "zh-Hans"
                XCTAssertTrue(app.staticTexts[chinese ? "未连接" : "Not connected"].exists)
                let status = app.staticTexts["home-connection-status"]
                XCTAssertTrue(status.label.contains(chinese ? "无法连接服务器。" : "Couldn't reach the server."))
                let retry = app.buttons["pending-retry"]
                XCTAssertTrue(retry.isHittable)
                XCTAssertGreaterThanOrEqual(retry.frame.height, 44)
                let settings = recoverySettings(app, language: language)
                XCTAssertTrue(settings.isHittable)
                XCTAssertGreaterThanOrEqual(settings.frame.height, 44)
                XCTAssertLessThan(settings.frame.maxY, app.tabBars.firstMatch.frame.minY)
                XCTAssertFalse(app.staticTexts[chinese ? "没有需要你处理的事" : "Nothing needs you"].exists)
                keepRecoveryScreenshot(app, "\(chinese ? "zh" : "en")-home-failed-ax-\(appearance)")
                settings.tap()
                XCTAssertTrue(app.buttons["settings-connection"].waitForExistence(timeout: 5))
                app.terminate()
            }
        }
    }

    private func launchRecoveryState(
        _ state: String, language: String = "en", appearance: String = "Light", largeText: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.configureDemoLaunch(["HIBOSS_DEMO_EMPTY": "1", "HIBOSS_DEMO_CONNECTION": state])
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale",
                               language == "en" ? "en_US" : "zh_CN", "-AppleInterfaceStyle", appearance]
        if largeText {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL",
            ]
        }
        app.launchConfiguredDemo()
        XCTAssertTrue(app.staticTexts["home-connection-status"].waitForExistence(timeout: 5))
        return app
    }

    private func recoverySettings(_ app: XCUIApplication, language: String = "en") -> XCUIElement {
        app.scrollViews.buttons.matching(
            NSPredicate(format: "label == %@ AND identifier != %@",
                        language == "en" ? "Settings" : "设置", "today-settings")
        ).firstMatch
    }

    private func keepRecoveryScreenshot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

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
