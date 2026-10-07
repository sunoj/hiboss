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
        continueAfterFailure = false
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

    func testTourChineseLargeText() {
        tour(prefix: appearancePrefix + "zh-xxl", extra: [:], arguments: Self.chinese + Self.largeText)
    }

    func testTourEmptyEnglish() {
        tour(prefix: appearancePrefix + "en-empty", extra: ["HIBOSS_DEMO_EMPTY": "1"])
    }

    /// One extra language per run, chosen by `UX_TOUR_LANG` (e.g. `ar`, `pt-BR`); skipped when unset.
    func testTourLanguage() throws {
        guard let language = ProcessInfo.processInfo.environment["UX_TOUR_LANG"].flatMap({ $0.isEmpty ? nil : $0 }) else {
            throw XCTSkip("set UX_TOUR_LANG to run this tour")
        }
        tour(prefix: appearancePrefix + language, extra: [:],
             arguments: ["-AppleLanguages", "(\(language))", "-AppleLocale", language.replacingOccurrences(of: "-", with: "_")])
    }

    /// Home and Messages in the two non-connected states the demo can simulate.
    func testTourConnectionStates() {
        for state in ["failed", "connecting"] {
            launchFresh(["HIBOSS_DEMO_CONNECTION": state], arguments: Self.chinese)
            let messages = app.tabBars.buttons.element(boundBy: 1)
            guard messages.waitForExistence(timeout: 8) else { continue }
            settle()
            shot("\(appearancePrefix)conn-\(state)-01-home")
            messages.tap()
            selectMessages()
            settle()
            shot("\(appearancePrefix)conn-\(state)-04-messages")
            app.terminate()
        }
    }

    /// A refresh that fails after a successful load: the list keeps its rows and says so.
    func testTourStaleRefresh() {
        launchFresh(["HIBOSS_DEMO_REFRESH_FAILS": "1"])
        let messages = app.tabBars.buttons.element(boundBy: 1)
        XCTAssertTrue(messages.waitForExistence(timeout: 8))
        messages.tap()
        selectMessages()
        Thread.sleep(forTimeInterval: 5)
        pullToRefresh(app)
        settle()
        Thread.sleep(forTimeInterval: 2)  // the refresh control animates back after the failure
        shot("\(appearancePrefix)conn-stale-04-messages")
    }

    /// First run: the connect screen, at the default and the largest tour text size.
    func testTourOnboarding() {
        for (name, arguments) in [("en", [String]()), ("xxl", Self.largeText)] {
            launchFresh(["HIBOSS_DEMO_ONBOARDING": "1"], arguments: arguments)
            XCTAssertTrue(app.textFields["server-url-field"].waitForExistence(timeout: 8))
            settle()
            shot("\(appearancePrefix)\(name)-00-onboarding")
            app.terminate()
        }
    }

    /// Settings → Pair another device, Device Requests and its review sheet, then Sign Out.
    func testTourDevices() {
        launchFresh([:])
        openSettingsRow("Pair another device")
        shot("\(appearancePrefix)en-14-pair-device")
        app.navigationBars.buttons.firstMatch.tap()
        openSettingsRow("Device Requests")
        shot("\(appearancePrefix)en-17-device-requests")
        let request = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'build-box-2'")).firstMatch
        if request.waitForExistence(timeout: 4) {
            request.tap()
            settle()
            shot("\(appearancePrefix)en-18-device-review")
            app.buttons["Close"].firstMatch.tap()
            settle()
        }
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        for _ in 0..<6 where !app.buttons["settings-sign-out"].isHittable { app.swipeUp() }
        app.buttons["settings-sign-out"].tap()
        settle()
        shot("\(appearancePrefix)en-19-sign-out")
    }

    /// A pairing code that runs out while the screen is open.
    func testTourPairingExpired() {
        launchFresh(["HIBOSS_DEMO_PAIRING_TTL": "3"])
        openSettingsRow("Pair another device")
        Thread.sleep(forTimeInterval: 4)
        shot("\(appearancePrefix)en-21-pair-expired")
    }

    /// A decision the server settled with its timeout default, in detail and in Resolved.
    func testTourAutoDecided() {
        launchFresh(["HIBOSS_DEMO_OPEN": "a1"])
        XCTAssertTrue(app.staticTexts["message-question"].waitForExistence(timeout: 8))
        settle()
        shot("\(appearancePrefix)en-18-auto-decided-detail")
        app.terminate()
        launchFresh(["HIBOSS_DEMO_RESOLVED": "1"])
        settle()
        for _ in 0..<4 where !app.staticTexts["Rotate the export bucket key before tonight's run?"].isHittable {
            app.swipeUp()
        }
        shot("\(appearancePrefix)en-19-resolved-auto-decided")
    }

    func testTourEmpty() {
        tour(prefix: appearancePrefix + "empty", extra: ["HIBOSS_DEMO_EMPTY": "1"],
             arguments: ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"])
    }

    func testTourLargeText() {
        tour(prefix: appearancePrefix + "xxl", extra: [:], arguments: Self.largeText)
    }

    private static let chinese = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    private static let largeText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]

    /// Launches demo mode; relaunches once if the first launch lost its environment.
    private func launchFresh(_ extra: [String: String], arguments: [String] = []) {
        app = XCUIApplication()
        app.configureDemoLaunch(extra)
        app.launchArguments += arguments
        app.launchConfiguredDemo()
    }

    private func openSettingsRow(_ title: String) {
        let settings = app.tabBars.buttons.element(boundBy: 3)
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()
        if app.buttons["settings-devices"].exists { app.buttons["settings-devices"].tap() }
        let row = app.buttons[title].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "missing Settings row \(title)")
        row.tap()
        settle()
    }

    private func tour(prefix: String, extra: [String: String], arguments: [String] = []) {
        app.configureDemoLaunch(extra)
        app.launchArguments += arguments
        app.launchConfiguredDemo()
        settle()
        shot("\(prefix)-01-home")
        app.swipeUp()
        settle()
        shot("\(prefix)-02-home-scrolled")
        app.swipeDown()
        if extra["HIBOSS_DEMO_EMPTY"] != "1" { openFirstHomeItem(prefix: prefix) }
        tourActivity(prefix: prefix)
        // Progress remains one tap away; Settings is the final tab.
        for (index, name) in ["progress", "settings"].enumerated() {
            let tab = app.tabBars.buttons.element(boundBy: index + 2)
            XCTAssertTrue(tab.waitForExistence(timeout: 5), "missing tour tab \(name)")
            tab.tap()
            settle()
            shot("\(prefix)-\(name == "progress" ? "06" : "10")-\(name)")
            switch name {
            case "progress": openFirstImage(prefix: prefix)
            default: tourSettingsDetails(prefix: prefix)
            }
        }
    }

    private func tourActivity(prefix: String) {
        let activity = app.tabBars.buttons.element(boundBy: 1)
        XCTAssertTrue(activity.waitForExistence(timeout: 5))
        activity.tap()
        settle()
        shot("\(prefix)-08-sessions")
        openFirstRow(prefix: prefix, name: "sessions", index: 2)
        selectMessages()
        settle()
        shot("\(prefix)-04-messages")
        openFirstRow(prefix: prefix, name: "messages", index: 0)
    }

    private func selectMessages() {
        let segment = app.segmentedControls.buttons.element(boundBy: 1)
        if segment.exists {
            segment.tap()
        } else {
            app.buttons["activity-section"].firstMatch.tap()
            app.buttons.matching(NSPredicate(format: "label == 'Messages' OR label == '消息'")).firstMatch.tap()
        }
    }

    private func openFirstHomeItem(prefix: String) {
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'home-message-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "populated Home requires a decision row")
        row.tap()
        settle()
        XCTAssertTrue(app.staticTexts["message-question"].waitForExistence(timeout: 5))
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
        // The first feed image by its alt text: `app.images.firstMatch` can be a tab-bar glyph.
        let image = app.images["wide landscape screenshot"].firstMatch
        guard image.waitForExistence(timeout: 4), image.isHittable else { return }
        image.tap()
        settle()
        shot("\(prefix)-07-progress-media")
        app.swipeDown()
        settle()
    }

    private func tourSettingsDetails(prefix: String) {
        app.buttons["settings-connection"].tap()
        settle()
        shot("\(prefix)-11-settings-connection")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["settings-notifications"].tap()
        settle()
        shot("\(prefix)-12-settings-notifications")
    }

    private func settle() { _ = app.wait(for: .runningForeground, timeout: 3); Thread.sleep(forTimeInterval: 1.2) }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
