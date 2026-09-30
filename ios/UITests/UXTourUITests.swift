// Screenshot tour of every tab and the main flows, for UX review.
// Exports: UXTourUITests (attachments named "<nn>-<surface>", kept on success).
// Dependencies: XCTest, DemoLaunchSupport.

import XCTest

/// Not an assertion suite: it walks the app the way a boss would and keeps a
/// screenshot of each stop, so a UI change is judged by looking, not by reading
/// the diff. Export with `xcrun xcresulttool export attachments`.
final class UXTourUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
    }

    /// Appearance is the simulator's (`xcrun simctl ui booted appearance dark`), so the
    /// prefix comes from `UX_TOUR_PREFIX` when a run sets it; launch arguments cannot
    /// switch an iOS app to dark mode.
    private var appearancePrefix: String { ProcessInfo.processInfo.environment["UX_TOUR_PREFIX"] ?? "" }

    func testTourPopulated() { tour(prefix: appearancePrefix + "en", extra: [:]) }

    func testTourChinese() {
        tour(prefix: appearancePrefix + "zh", extra: [:],
             arguments: ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"])
    }

    func testTourEmpty() {
        tour(prefix: appearancePrefix + "empty", extra: ["HIBOSS_DEMO_EMPTY": "1"],
             arguments: ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"])
    }

    func testTourLargeText() {
        tour(prefix: appearancePrefix + "xxl", extra: [:],
             arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
    }

    private func tour(prefix: String, extra: [String: String], arguments: [String] = []) {
        app.configureDemoLaunch(extra)
        app.launchArguments += arguments
        app.launch()
        settle()
        shot("\(prefix)-01-home")
        app.swipeUp()
        settle()
        shot("\(prefix)-02-home-scrolled")
        app.swipeDown()
        openFirstHomeItem(prefix: prefix)
        // Tabs by position: labels are localised, the order is fixed by RootTabView.
        for (index, name) in ["messages", "progress", "sessions", "settings"].enumerated() {
            let tab = app.tabBars.buttons.element(boundBy: index + 1)
            guard tab.waitForExistence(timeout: 5) else { continue }
            tab.tap()
            settle()
            shot("\(prefix)-\(String(format: "%02d", index * 2 + 4))-\(name)")
            switch name {
            case "messages", "sessions": openFirstRow(prefix: prefix, name: name, index: index)
            case "progress": openFirstImage(prefix: prefix)
            default: scrollAndShoot(prefix: prefix, name: name)
            }
        }
    }

    private func openFirstHomeItem(prefix: String) {
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'home-message-'")).firstMatch
        guard row.waitForExistence(timeout: 5) else { return }
        row.tap()
        settle()
        shot("\(prefix)-03-home-detail")
        app.navigationBars.buttons.firstMatch.tap()
        settle()
    }

    private func openFirstRow(prefix: String, name: String, index: Int) {
        let row = app.cells.firstMatch.exists ? app.cells.firstMatch : app.collectionViews.buttons.firstMatch
        guard row.waitForExistence(timeout: 4), row.isHittable else { return }
        row.tap()
        settle()
        shot("\(prefix)-\(String(format: "%02d", index * 2 + 5))-\(name.lowercased())-detail")
        if app.navigationBars.buttons.firstMatch.exists {
            app.navigationBars.buttons.firstMatch.tap()
        } else {
            app.swipeDown()
        }
        settle()
    }

    private func openFirstImage(prefix: String) {
        let image = app.images.firstMatch
        guard image.waitForExistence(timeout: 4), image.isHittable else { return }
        image.tap()
        settle()
        shot("\(prefix)-07-progress-media")
        app.swipeDown()
        settle()
    }

    private func scrollAndShoot(prefix: String, name: String) {
        app.swipeUp()
        settle()
        shot("\(prefix)-11-\(name)-scrolled")
        app.swipeUp()
        settle()
        shot("\(prefix)-12-\(name)-bottom")
    }

    private func settle() { _ = app.wait(for: .runningForeground, timeout: 3); Thread.sleep(forTimeInterval: 1.2) }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
