// Onboarding loading captures and inventory-only evidence for Settings-owned flows.
// Exports IntermediateOnboardingUITests; Settings views are never modified by this task.
// Dependencies: IntermediateCaptureCase and delayed demo device services.

import XCTest

final class IntermediateOnboardingUITests: IntermediateCaptureCase {
    func testLiveActivityControls() {
        launch(["HIBOSS_DEMO_ACTIVITY": "1"])
        holdAndCapture("activity-reply")
    }

    func testRestoreAndConnect() {
        launch(["HIBOSS_DEMO_RESTORE_DELAY_MS": "60000"])
        holdAndCapture("restore")
        launch(["HIBOSS_DEMO_ONBOARDING": "1", "HIBOSS_DEMO_CONNECT_DELAY_MS": "60000"])
        let connect = app.buttons[variant.contains("zh") ? "连接" : "Connect"].firstMatch
        XCTAssertTrue(connect.waitForExistence(timeout: 8))
        connect.tap()
        holdAndCapture("onboarding-connect")
    }

    func testOwnedPairingAndRequests() {
        launch(["HIBOSS_DEMO_PAIRING_DELAY_MS": "60000"])
        openSettings(variant.contains("zh") ? "配对其他设备" : "Pair another device")
        holdAndCapture("owned-pairing-code")
        launch(["HIBOSS_DEMO_PAIRING_POLL_DELAY_MS": "60000"])
        openSettings(variant.contains("zh") ? "配对其他设备" : "Pair another device")
        holdAndCapture("owned-pairing-poll")
        launch(["HIBOSS_DEMO_DEVICES_DELAY_MS": "60000"])
        openSettings(variant.contains("zh") ? "设备请求" : "Device Requests")
        holdAndCapture("owned-devices-load")
        launch(["HIBOSS_DEMO_JOIN_REQUEST": "jr-build", "HIBOSS_DEMO_DEVICES_DELAY_MS": "60000"])
        holdAndCapture("owned-device-detail")
        launch(["HIBOSS_DEMO_JOIN_REQUEST": "jr-build", "HIBOSS_DEMO_DEVICE_ACTION_DELAY_MS": "60000"])
        let approve = app.buttons["join-request.approve"].firstMatch
        reveal(approve)
        approve.tap()
        holdAndCapture("owned-device-approve")
    }

    func testOwnedSignin() {
        let link = "hiboss://signin?server=https%3A%2F%2Fhiboss.example.com&request="
            + String(repeating: "a", count: 32)
        launch(["HIBOSS_DEMO_SIGNIN_SCAN": link, "HIBOSS_DEMO_SIGNIN_DELAY_MS": "60000"])
        openSettings(variant.contains("zh") ? "登录 Mac" : "Sign in a Mac")
        holdAndCapture("owned-signin-load")
        launch(["HIBOSS_DEMO_SIGNIN_SCAN": link, "HIBOSS_DEMO_SIGNIN_ACTION_DELAY_MS": "60000"])
        openSettings(variant.contains("zh") ? "登录 Mac" : "Sign in a Mac")
        let approve = app.buttons["mac-signin.approve"].firstMatch
        reveal(approve)
        approve.tap()
        holdAndCapture("owned-signin-approve")
    }

    func testOwnedPreferencesAndCamera() {
        launch(["HIBOSS_DEMO_PREFERENCES_DELAY_MS": "120000"])
        app.tabBars.buttons.element(boundBy: 3).tap()
        let loading = app.staticTexts[variant.contains("zh") ? "正在加载偏好设置…" : "Loading preferences…"]
        reveal(loading)
        holdAndCapture("owned-preferences-load")
        XCTAssertTrue(loading.exists, "The capture hook must still hold the read after the slow screenshot")
        launch(["HIBOSS_DEMO_PREFERENCES_SAVE_DELAY_MS": "60000"])
        app.tabBars.buttons.element(boundBy: 3).tap()
        let toggle = app.switches[variant.contains("zh") ? "私密通知" : "Private Notifications"].firstMatch
        reveal(toggle)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let save = app.buttons[variant.contains("zh") ? "保存更改" : "Save Changes"].firstMatch
        reveal(save)
        save.tap()
        holdAndCapture("owned-preferences-save")
        let saving = app.buttons[variant.contains("zh") ? "正在保存…" : "Saving…"].firstMatch
        XCTAssertTrue(saving.exists, "The capture hook must still hold the write")
        launch(["HIBOSS_DEMO_ONBOARDING": "1", "HIBOSS_DEMO_CAMERA_DELAY_MS": "60000"])
        let scanner = app.buttons[variant.contains("zh") ? "扫码" : "Scan a code"].firstMatch
        reveal(scanner)
        scanner.tap()
        holdAndCapture("owned-camera-permission")
    }

    func testOwnedNotificationRegistration() {
        launch(["HIBOSS_DEMO_PUSH_DELAY_MS": "60000"])
        let permission = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if permission.waitForExistence(timeout: 2) {
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "\(variant)-owned-notification-permission"
            shot.lifetime = .keepAlways
            add(shot)
            let allow = permission.buttons["Allow"].exists
                ? permission.buttons["Allow"] : permission.buttons["允许"]
            allow.tap()
        }
        launch(["HIBOSS_DEMO_PUSH_DELAY_MS": "60000"])
        app.tabBars.buttons.element(boundBy: 3).tap()
        let label = variant.contains("zh") ? "正在注册…" : "Registering…"
        let registering = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
        reveal(registering)
        holdAndCapture("owned-push-register")
    }

    private func openSettings(_ label: String) {
        app.tabBars.buttons.element(boundBy: 3).tap()
        let row = app.buttons[label].firstMatch
        for _ in 0..<8 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
    }
}
