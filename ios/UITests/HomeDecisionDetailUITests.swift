// Chinese Home -> message detail flow: navigation stays on Home, timing and default agree.
// Exports: HomeDecisionDetailUITests (Home tab stack, shared decision controls, empty panels).
// Dependencies: XCTest, DemoLaunchSupport.

import XCTest

final class HomeDecisionDetailUITests: XCTestCase {
    private static let chinese = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    private static let accessibilityXXXL = [
        "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
    ]
    private static let c5Question = "Which release banner grid should ship — coarse blocks or a fine weave?"
    private static let c1Question =
        "Production deploy will DROP 3 history tables (orders_2023 +2), irreversible. Run migration?"
    private static let autoSelectCopy = "到时自动选择「Coarse grid」"

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ extra: [String: String] = [:], arguments: [String] = []) {
        app.configureDemoLaunch(extra)
        let textSize = arguments.contains("-UIPreferredContentSizeCategoryName") ? [] : [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
        ]
        app.launchArguments += Self.chinese + textSize + arguments
        app.launch()
    }

    private func timing(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "decision-timing-\(id)").firstMatch
    }

    func testChineseHomeOpensDetailOnHomeStackAndBackReturnsHome() {
        launch()
        XCTAssertTrue(app.staticTexts["待你处理"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["4 项等你决定"].exists, "count uses the localized plural")
        XCTAssertTrue(app.staticTexts["即将自动决定"].exists, "section header is localized")

        XCTAssertTrue(timing("c5").waitForExistence(timeout: 5))
        XCTAssertTrue(timing("c5").label.contains(Self.autoSelectCopy), timing("c5").label)
        XCTAssertTrue(timing("c5").label.contains("剩余"))
        XCTAssertEqual(app.buttons["Coarse grid"].value as? String, "默认", "Home marks the live default")
        XCTAssertNotEqual(app.buttons["Fine grid"].value as? String, "默认")
        assertSideBySide("Coarse grid", "Fine grid")

        app.buttons["home-message-c5"].tap()
        let question = app.staticTexts["message-question"]
        XCTAssertTrue(question.waitForExistence(timeout: 5), "detail opens from Home")
        XCTAssertEqual(question.label, Self.c5Question)
        XCTAssertTrue(app.navigationBars["prod-release"].exists, "detail title is the session")
        XCTAssertTrue(app.tabBars.buttons["首页"].isSelected, "opening a decision keeps the Home tab")

        XCTAssertTrue(timing("c5").label.contains(Self.autoSelectCopy), "detail repeats Home's timing copy")
        XCTAssertTrue(timing("c5").label.contains("剩余"))
        XCTAssertEqual(app.buttons["Coarse grid"].value as? String, "默认", "detail marks the same default")
        assertSideBySide("Coarse grid", "Fine grid")
        XCTAssertTrue(app.descendants(matching: .any)["message-more-information"].exists)
        XCTAssertFalse(app.staticTexts["方向"].exists, "routing facts stay collapsed")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["待你处理"].waitForExistence(timeout: 5), "back returns to Home")
        XCTAssertTrue(app.tabBars.buttons["首页"].isSelected)
        XCTAssertFalse(question.exists)
    }

    func testDetailLabelsAreLocalized() {
        launch()
        XCTAssertTrue(app.buttons["home-message-c5"].waitForExistence(timeout: 10))
        app.buttons["home-message-c5"].tap()
        XCTAssertTrue(app.staticTexts["message-question"].waitForExistence(timeout: 5))
        for _ in 0..<6 where !app.staticTexts["优先级"].exists { app.swipeUp() }
        for label in ["详情", "智能体", "会话", "分支", "提问时间", "优先级"] {
            XCTAssertTrue(app.staticTexts[label].exists, "missing localized label \(label)")
        }
        XCTAssertFalse(app.staticTexts["Agent"].exists)
        XCTAssertFalse(app.staticTexts["Priority"].exists)
    }

    /// Measured on iPhone 17 at Accessibility XXXL: the full c1 question makes its Home row ~10
    /// answer-button heights tall and its detail text ~8; a three-line clip stays under ~5.
    func testFullQuestionAtAccessibilitySizeOnHomeAndDetail() {
        launch(arguments: Self.accessibilityXXXL)
        let row = app.buttons["home-message-c1"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains(Self.c1Question))
        let reply = app.buttons["Approve"]
        assertSideBySide("Approve", "Reject")
        keepScreenshot("accessibility-home-question")
        XCTAssertGreaterThan(row.frame.height, reply.frame.height * 6, "Home question must not truncate")

        for _ in 0..<8 where !row.isHittable { app.swipeUp() }
        row.tap()
        let detailQuestion = app.staticTexts["message-question"]
        XCTAssertTrue(detailQuestion.waitForExistence(timeout: 5))
        XCTAssertEqual(detailQuestion.label, Self.c1Question)
        keepScreenshot("accessibility-detail-question")
        XCTAssertGreaterThan(detailQuestion.frame.height, reply.frame.height * 5, "detail question must not truncate")
        XCTAssertGreaterThanOrEqual(app.buttons["Approve"].frame.height, 44)
        assertSideBySide("Approve", "Reject")
        XCTAssertLessThanOrEqual(detailQuestion.frame.width, app.frame.width)
    }

    func testNoPanelControlsWithoutPanels() {
        launch()
        XCTAssertTrue(app.staticTexts["待你处理"].waitForExistence(timeout: 10))
        assertNoPanelControls()

        app.terminate()
        launch(["HIBOSS_DEMO_EMPTY": "1"])
        XCTAssertTrue(app.staticTexts["没有需要你处理的事"].waitForExistence(timeout: 10))
        assertNoPanelControls()
    }

    func testBackRestoresScrolledHomeLocation() {
        launch()
        let row = app.buttons["home-message-c2"]
        XCTAssertTrue(app.staticTexts["待你处理"].waitForExistence(timeout: 10))
        for _ in 0..<8 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.isHittable)
        let originalY = row.frame.minY
        row.tap()
        XCTAssertTrue(app.staticTexts["message-question"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["首页"].isSelected)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.frame.minY, originalY, accuracy: 3, "back preserves Home scroll position")
        XCTAssertTrue(app.tabBars.buttons["首页"].isSelected)
    }

    func testWaitingTimingWithoutDeadlineAgreesOnHomeAndDetail() {
        launch()
        let row = app.buttons["home-message-c3"]
        XCTAssertTrue(app.staticTexts["待你处理"].waitForExistence(timeout: 10))
        for _ in 0..<8 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(timing("c3").label.contains("已等待"))
        XCTAssertFalse(timing("c3").label.contains("自动选择"))
        XCTAssertNotEqual(app.buttons["Provide"].value as? String, "默认")
        row.tap()
        XCTAssertTrue(app.staticTexts["message-question"].waitForExistence(timeout: 5))
        XCTAssertTrue(timing("c3").label.contains("已等待"))
        XCTAssertFalse(timing("c3").label.contains("自动选择"))
        XCTAssertNotEqual(app.buttons["Provide"].value as? String, "默认")
    }

    private func keepScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertSideBySide(_ first: String, _ second: String) {
        let left = app.buttons[first].frame
        let right = app.buttons[second].frame
        XCTAssertGreaterThanOrEqual(left.width, 44)
        XCTAssertGreaterThanOrEqual(right.width, 44)
        XCTAssertGreaterThanOrEqual(left.height, 44)
        XCTAssertGreaterThanOrEqual(right.height, 44)
        XCTAssertEqual(left.midY, right.midY, accuracy: 2, "two choices share the same row")
        XCTAssertLessThanOrEqual(left.maxX, right.minX, "choice buttons do not overlap")
        XCTAssertGreaterThanOrEqual(left.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(right.maxX, app.frame.maxX)
    }

    private func assertNoPanelControls() {
        // Give the panel load a moment to finish so an empty wall would have rendered.
        _ = app.staticTexts["实时面板"].waitForExistence(timeout: 2)
        XCTAssertFalse(app.staticTexts["实时面板"].exists, "no panels header without tiles")
        XCTAssertEqual(app.segmentedControls.count, 0, "no panel filter without tiles")
        XCTAssertFalse(app.buttons["刷新"].exists)
        XCTAssertFalse(app.buttons["Refresh"].exists)
    }
}
