// Screenshot coverage of Settings and every device and notification subpage.
// Exports: SettingsTourUITests with English/Chinese and accessibility L variants.
// Dependencies: XCTest, DemoLaunchSupport; appearance follows the simulator.

import XCTest

final class SettingsTourUITests: XCTestCase {
    private var app: XCUIApplication!
    private var prefix = ""

    func testEnglish() { tour(language: "en", large: false) }
    func testChinese() { tour(language: "zh-Hans", large: false) }
    func testEnglishLarge() { tour(language: "en", large: true) }
    func testChineseLarge() { tour(language: "zh-Hans", large: true) }

    private func tour(language: String, large: Bool) {
        continueAfterFailure = false
        app = XCUIApplication()
        prefix = language + (large ? "-axL" : "")
        let request = String(repeating: "ab", count: 16)
        app.configureDemoLaunch([
            "HIBOSS_DEMO_SIGNIN_SCAN":
                "hiboss://signin?server=https%3A%2F%2Fhiboss.example.com&request=\(request)",
        ])
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", language]
        if large {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        }
        app.launchConfiguredDemo()
        XCTAssertTrue(app.tabBars.buttons.element(boundBy: 3).waitForExistence(timeout: 8))
        app.tabBars.buttons.element(boundBy: 3).tap()
        shot("10-settings")
        let redesigned = app.buttons["settings-devices"].exists
        if redesigned {
            open("settings-connection")
            shot("11-connection")
            back()
            open("settings-notifications")
            shot("12-notifications")
            app.swipeUp()
            shot("12-notifications-bottom")
            open("settings-delivery")
            shot("12-delivery")
            app.swipeUp()
            shot("12-delivery-bottom")
            back()
            back()
            open("settings-about")
            shot("12-about")
            back()
            open("settings-devices")
            shot("13-devices")
        } else {
            app.swipeUp()
            shot("11-settings-scrolled")
            app.swipeUp()
            shot("12-settings-bottom")
            app.swipeDown()
            app.swipeDown()
        }
        deviceScreens(language: language, redesigned: redesigned)
    }

    private func deviceScreens(language: String, redesigned: Bool) {
        open(language == "en" ? "Pair another device" : "配对其他设备")
        XCTAssertTrue(app.buttons[language == "en" ? "Copy Link" : "复制链接"].waitForExistence(timeout: 8))
        shot("14-pair-device")
        back()
        open(language == "en" ? "Sign in a Mac" : "登录 Mac")
        XCTAssertTrue(app.buttons["mac-signin.approve"].waitForExistence(timeout: 8))
        shot("15-mac-review")
        app.buttons["mac-signin.approve"].tap()
        XCTAssertTrue(app.staticTexts["mac-signin.code"].waitForExistence(timeout: 8))
        shot("16-mac-code")
        app.buttons["mac-signin.done"].tap()
        open(language == "en" ? "Device Requests" : "设备请求")
        shot("17-device-requests")
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'build-box-2'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
        XCTAssertTrue(app.staticTexts["join-request.code"].waitForExistence(timeout: 8))
        shot("18-device-review")
        app.navigationBars.buttons.firstMatch.tap()
        back()
        if redesigned { back() }
        open("settings-sign-out")
        shot("19-sign-out")
        app.terminate()
    }

    private func open(_ identifier: String) {
        let button = app.buttons[identifier].firstMatch
        for _ in 0..<8 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.waitForExistence(timeout: 8), identifier)
        button.tap()
    }

    private func back() { app.navigationBars.buttons.firstMatch.tap() }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "\(prefix)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
