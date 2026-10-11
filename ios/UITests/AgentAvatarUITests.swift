// Captures a demo agent's registered image in the native message list.
// Dependencies: XCTest, offline demo fixtures, and shared demo launch support.

import XCTest

@MainActor
final class AgentAvatarUITests: XCTestCase {
    func testDemoRegisteredAvatarInMessageList() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.configureDemoLaunch()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleInterfaceStyle", "Light"]
        app.launchConfiguredDemo()
        app.tabBars.buttons["Sessions"].tap()
        app.buttons["Messages"].tap()
        XCTAssertTrue(app.staticTexts["worker-design"].firstMatch.waitForExistence(timeout: 10))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "registered-agent-avatar-ios"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
