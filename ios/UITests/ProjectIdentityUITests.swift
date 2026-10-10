// Project avatar and nickname flows with recent peer preview and full-list evidence.
// Exports ProjectIdentityUITests; depends on XCTest and offline demo inventory.

import XCTest

@MainActor
final class ProjectIdentityUITests: XCTestCase {
    func testLightSessionsAndPeers() { capture("Light") }
    func testDarkSessionsAndPeers() { capture("Dark") }
    func testChinesePeersAtAccessibilityTextSize() {
        continueAfterFailure = false
        let app = launch("Light", language: "zh-Hans", largeText: true)
        app.tabBars.buttons["会话"].tap()
        app.buttons["activity-session-sess-deploy"].tap()
        let peers = app.descendants(matching: .any).matching(identifier: "project-peers").firstMatch
        for _ in 0..<8 where !peers.exists || !peers.isHittable { app.swipeDown() }
        XCTAssertTrue(peers.waitForExistence(timeout: 10), app.debugDescription)
        peers.tap()
        let all = app.buttons["project-peers-show-all"]
        for _ in 0..<8 where !all.isHittable { app.swipeUp() }
        XCTAssertTrue(all.isHittable)
        all.tap()
        XCTAssertTrue(app.navigationBars["最近活跃的会话"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["prod-release · palm"].exists)
        shot(app, "zh-large-peers")
    }

    private func capture(_ appearance: String) {
        continueAfterFailure = false
        let app = launch(appearance)
        app.tabBars.buttons["Sessions"].tap()
        let session = app.buttons["activity-session-sess-deploy"]
        XCTAssertTrue(session.waitForExistence(timeout: 10))
        XCTAssertTrue(session.label.contains("prod-release · otter"))
        shot(app, "\(appearance)-sessions")
        session.tap()
        XCTAssertTrue(app.staticTexts["prod-release · otter"].waitForExistence(timeout: 10))
        let peers = app.descendants(matching: .any).matching(identifier: "project-peers").firstMatch
        for _ in 0..<8 where !peers.exists || !peers.isHittable { app.swipeDown() }
        XCTAssertTrue(peers.waitForExistence(timeout: 10), app.debugDescription)
        peers.tap()
        XCTAssertTrue(app.descendants(matching: .any)["project-peer-peer-1"]
            .waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["project-peer-peer-6"].exists)
        shot(app, "\(appearance)-session-peers")
        let all = app.buttons["project-peers-show-all"]
        for _ in 0..<8 where !all.isHittable { app.swipeUp() }
        XCTAssertTrue(all.isHittable)
        all.tap()
        XCTAssertTrue(app.navigationBars["Recent peers"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["prod-release · fern"].exists)
        XCTAssertFalse(app.staticTexts["prod-release · otter"].exists)
        app.terminate()
    }

    private func launch(_ appearance: String, language: String = "en", largeText: Bool = false)
        -> XCUIApplication {
        let app = XCUIApplication()
        app.configureDemoLaunch(["HIBOSS_DEMO_PEERS": "1"])
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleInterfaceStyle", appearance]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName",
                                    "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launchConfiguredDemo()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        return app
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "avatar-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
