// Shared behavioral assertions for every media entry point's UIKit zoom surface.
// Exports zoom assertions and MediaViewerActionBarUITests for localized single-line action coverage.
// Dependencies: XCTest and the shared MediaViewer accessibility contract.

import XCTest
import UIKit

func mediaZoomScroll(_ app: XCUIApplication) -> XCUIElement {
    let query = app.scrollViews.matching(NSPredicate(
        format: "identifier BEGINSWITH %@", "media-zoom-scroll"
    ))
    _ = query.firstMatch.waitForExistence(timeout: 5)
    return query.allElementsBoundByIndex.first { $0.isHittable } ?? query.firstMatch
}

func assertMediaPinchZoom(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    let scroll = mediaZoomScroll(app)
    XCTAssertTrue(scroll.exists, file: file, line: line)
    scroll.pinch(withScale: 2, velocity: 1)
    let zoomed = NSPredicate(format: "value == %@", "Zoomed")
    let expectation = XCTNSPredicateExpectation(predicate: zoomed, object: scroll)
    XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed, file: file, line: line)
}

final class MediaViewerActionBarUITests: XCTestCase {
    func testActionLabelsStayOnOneLineInEnglishAndChinese() {
        continueAfterFailure = false
        for language in ["en", "zh-Hans"] {
            for category in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryXXXL",
                             "UICTContentSizeCategoryAccessibilityL"] {
                let app = XCUIApplication()
                app.configureDemoLaunch(["HIBOSS_DEMO_BOX_V2": "1"])
                app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", language,
                                       "-UIPreferredContentSizeCategoryName", category]
                app.launchConfiguredDemo()
                let box = app.tabBars.buttons.element(boundBy: 2)
                XCTAssertTrue(box.waitForExistence(timeout: 10))
                box.tap()
                let image = app.buttons["box-item-demo-image"]
                XCTAssertTrue(image.waitForExistence(timeout: 10))
                for _ in 0..<6 where !image.isHittable { app.swipeUp() }
                image.tap()
                XCTAssertTrue(app.buttons["media-viewer-close"].waitForExistence(timeout: 10))
                let size = UIContentSizeCategory(rawValue: category)
                let traits = UITraitCollection(preferredContentSizeCategory: size)
                let lineHeight = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits).lineHeight
                for action in ["copy", "info", "delete"] {
                    let button = app.buttons["media-viewer-\(action)"]
                    XCTAssertTrue(button.isHittable)
                    XCTAssertFalse(button.label.isEmpty)
                    for label in button.staticTexts.allElementsBoundByIndex {
                        XCTAssertLessThanOrEqual(label.frame.height, ceil(lineHeight) + 2,
                                                 "\(language) \(category) \(action) wraps")
                        XCTAssertLessThanOrEqual(label.frame.width, button.frame.width)
                    }
                    if category.contains("Accessibility") { XCTAssertEqual(button.staticTexts.count, 0) }
                }
                let shot = XCUIScreen.main.screenshot()
                let name = "viewer-bar-\(language)-\(category)"
                let attachment = XCTAttachment(screenshot: shot)
                attachment.name = name
                attachment.lifetime = .keepAlways
                add(attachment)
                app.terminate()
            }
        }
    }
}
