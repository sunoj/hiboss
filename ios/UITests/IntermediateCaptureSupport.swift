// Shared demo launch and attachment helpers for intermediate-state evidence.
// Exports IntermediateCaptureCase; uses bounded XCTest waits and launchConfiguredDemo.
// Dependencies: XCTest and deterministic HIBOSS_DEMO delay hooks.

import XCTest

class IntermediateCaptureCase: XCTestCase {
    var app: XCUIApplication!
    var variant: String { ProcessInfo.processInfo.environment["INTERMEDIATE_VARIANT"] ?? "en" }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func launch(_ extra: [String: String]) {
        app.terminate()
        app.configureDemoLaunch(extra)
        app.launchArguments = ["-AppleLanguages", variant.contains("zh") ? "(zh-Hans)" : "(en)"]
        if variant.contains("ax") {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL",
            ]
        }
        app.launchConfiguredDemo()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
        if extra["HIBOSS_DEMO_SESSION"] == "1" {
            XCTAssertTrue(app.navigationBars["prod-release"].waitForExistence(timeout: 8))
        }
        if extra["HIBOSS_TAB"] == "progress" {
            let title = variant.contains("zh") ? "进展" : "Progress"
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 8))
        }
    }

    func selectMessages() {
        let picker = app.segmentedControls.firstMatch
        if picker.exists { picker.buttons.element(boundBy: 1).tap() }
        else {
            app.buttons["activity-section"].tap()
            app.buttons[variant.contains("zh") ? "消息" : "Messages"].firstMatch.tap()
        }
    }

    func reveal(_ element: XCUIElement, upward: Bool = true) {
        for _ in 0..<20 {
            let bottom = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY : app.frame.maxY
            var moveUp = upward
            if element.exists {
                let center = element.frame.midY
                if element.isHittable && center > 110 && center < bottom - 12 { return }
                if element.frame.height > 0 && center > 0 && center < 110 { moveUp = false }
            }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: moveUp ? 0.7 : 0.3))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: moveUp ? 0.4 : 0.6))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTAssertTrue(element.waitForExistence(timeout: 3))
        XCTAssertTrue(element.isHittable)
    }

    func holdAndCapture(_ name: String) {
        pause(1)
        capture(name)
        pause(8)
        capture(name + "-slow")
    }

    func pause(_ seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        let pending = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in Date() >= deadline }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [pending], timeout: seconds + 2), .completed)
    }

    func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "\(variant)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
