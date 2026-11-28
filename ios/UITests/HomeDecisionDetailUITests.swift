// Chinese Home -> message detail flow: navigation stays on Home, timing and default agree.
// Exports: HomeDecisionDetailUITests (Home tab stack, shared decision controls, empty panels).
// Dependencies: XCTest, DemoLaunchSupport.

import XCTest

final class HomeDecisionDetailUITests: XCTestCase {
    private static let chinese = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    private static let accessibilityXXXL = [
        "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
    ]
    private static let c5Question = "发布横幅该用哪种网格：粗块还是细密编织？"
    private static let c1Question =
        "生产部署将删除 3 张历史表（orders_2023 等），不可恢复。执行迁移吗？"
    private static let autoSelectCopy = "将选择“粗网格”。这不代表批准。"

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
        app.launchConfiguredDemo()
    }

    private func timing(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "decision-timing-\(id)").firstMatch
    }

    func testChineseHomeOpensDetailOnHomeStackAndBackReturnsHome() {
        launch()
        XCTAssertTrue(app.staticTexts["由你决定"].appears(timeout: 10))
        XCTAssertTrue(app.staticTexts["4 项需要你"].exists, "count uses the localized plural")
        XCTAssertFalse(app.staticTexts["即将自动决定"].exists, "cards already describe their deadlines")

        XCTAssertTrue(timing("c5").appears(timeout: 5))
        XCTAssertTrue(timing("c5").label.contains(Self.autoSelectCopy), timing("c5").label)
        XCTAssertTrue(timing("c5").label.contains("内未回答"))
        XCTAssertEqual(app.buttons["粗网格"].value as? String, "默认", "Home marks the live default")
        XCTAssertNotEqual(app.buttons["细网格"].value as? String, "默认")
        assertFullWidth("粗网格", "细网格")

        app.buttons["home-message-c5"].tap()
        let question = app.staticTexts["message-question"]
        XCTAssertTrue(question.appears(timeout: 5), "detail opens from Home")
        XCTAssertEqual(question.label, Self.c5Question)
        XCTAssertTrue(app.navigationBars["prod-release"].exists, "detail title is the session")
        XCTAssertFalse(app.tabBars.firstMatch.isHittable, "the decision sheet covers the tab shell")

        XCTAssertTrue(timing("c5").label.contains(Self.autoSelectCopy), "detail repeats Home's timing copy")
        XCTAssertTrue(timing("c5").label.contains("内未回答"))
        XCTAssertEqual(app.buttons["粗网格"].value as? String, "默认", "detail marks the same default")
        assertFullWidth("粗网格", "细网格")
        XCTAssertTrue(app.descendants(matching: .any)["message-more-information"].exists)
        XCTAssertFalse(app.staticTexts["方向"].exists, "routing facts stay collapsed")

        app.navigationBars.buttons["完成"].tap()
        XCTAssertTrue(app.staticTexts["由你决定"].appears(timeout: 5), "back returns to Home")
        XCTAssertTrue(app.tabBars.buttons["今天"].isSelected)
        XCTAssertFalse(question.exists)
    }

    func testDetailLabelsAreLocalized() {
        launch()
        XCTAssertTrue(app.buttons["home-message-c5"].appears(timeout: 10))
        app.buttons["home-message-c5"].tap()
        XCTAssertTrue(app.staticTexts["message-question"].appears(timeout: 5))
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
        for _ in 0..<8 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.appears(timeout: 10))
        XCTAssertTrue(row.label.contains(Self.c1Question))
        keepScreenshot("accessibility-home-question")
        // A one-line row wraps its question at accessibility sizes instead of truncating it.
        XCTAssertGreaterThan(row.frame.height, 44 * 3, "Home question must not truncate")

        row.tap()
        let reply = app.buttons["批准"]
        let detailQuestion = app.staticTexts["message-question"]
        XCTAssertTrue(detailQuestion.appears(timeout: 5))
        XCTAssertEqual(detailQuestion.label, Self.c1Question)
        keepScreenshot("accessibility-detail-question")
        XCTAssertGreaterThan(
            detailQuestion.frame.height, reply.frame.height * 3, "detail question must not truncate"
        )
        for _ in 0..<8 where !app.buttons["批准"].isHittable { app.swipeUp() }
        XCTAssertGreaterThanOrEqual(app.buttons["批准"].frame.height, 44)
        assertFullWidth("批准", "拒绝")
        XCTAssertLessThanOrEqual(detailQuestion.frame.width, app.frame.width)
    }

    /// Choices share a row when they fit and wrap without overlap at accessibility sizes.
    func testTwoChoicesShareTheRowHeightAtAccessibilitySize() {
        launch(arguments: Self.accessibilityXXXL)
        let coarse = app.buttons["粗网格"].firstMatch
        XCTAssertTrue(coarse.appears(timeout: 10))
        for _ in 0..<8 where !coarse.isHittable { app.swipeUp() }
        keepScreenshot("accessibility-two-choices")
        assertSideBySide("粗网格", "细网格", allowsWrapping: true)
    }

    func testNoPanelControlsWithoutPanels() {
        launch()
        XCTAssertTrue(app.staticTexts["由你决定"].appears(timeout: 10))
        assertNoPanelControls()

        app.terminate()
        launch(["HIBOSS_DEMO_EMPTY": "1"])
        XCTAssertTrue(app.staticTexts["没有需要你处理的事"].appears(timeout: 10))
        assertNoPanelControls()
    }

    func testBackRestoresScrolledHomeLocation() {
        launch()
        let row = app.buttons["home-message-c2"]
        XCTAssertTrue(app.staticTexts["由你决定"].appears(timeout: 10))
        for _ in 0..<8 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.appears(timeout: 10))
        XCTAssertTrue(row.isHittable)
        let originalY = row.frame.minY
        row.tap()
        XCTAssertTrue(app.staticTexts["message-question"].appears(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["今天"].isSelected)
        app.navigationBars.buttons["完成"].tap()
        XCTAssertTrue(row.appears(timeout: 5))
        XCTAssertEqual(row.frame.minY, originalY, accuracy: 3, "back preserves Home scroll position")
        XCTAssertTrue(app.tabBars.buttons["今天"].isSelected)
    }

    func testWaitingTimingWithoutDeadlineAgreesOnHomeAndDetail() {
        launch()
        let row = app.buttons["home-message-c3"]
        XCTAssertTrue(app.staticTexts["由你决定"].appears(timeout: 10))
        for _ in 0..<8 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.appears(timeout: 10))
        // Today's one-line row names the missing deadline; it never promises an automatic choice.
        XCTAssertTrue(row.label.contains("无截止时间"))
        XCTAssertFalse(row.label.contains("自动选择"))
        row.tap()
        XCTAssertTrue(app.staticTexts["message-question"].appears(timeout: 5))
        XCTAssertTrue(timing("c3").label.contains("已等待"))
        XCTAssertFalse(timing("c3").label.contains("自动选择"))
        XCTAssertNotEqual(app.buttons["提供"].value as? String, "默认")
    }

    func testOptionDescriptionsLight() { verifyOptionDescriptions(style: "Light") }

    func testOptionDescriptionsDark() { verifyOptionDescriptions(style: "Dark") }

    func testOptionDescriptionsLargeText() {
        verifyOptionDescriptions(style: "Light", arguments: Self.accessibilityXXXL)
    }

    private func verifyOptionDescriptions(style: String, arguments: [String] = []) {
        launch(["HIBOSS_DEMO_STABLE_DEADLINES": "1"],
               arguments: arguments + ["-AppleInterfaceStyle", style])
        let choice = app.buttons["粗网格"]
        XCTAssertTrue(choice.appears(timeout: 10))
        XCTAssertTrue(choice.label.contains("更大的色块能突出每条公告。"))
        XCTAssertTrue(app.staticTexts["更大的色块能突出每条公告。"].firstMatch.exists)
        keepScreenshot("descriptions-home-\(style)-\(arguments.isEmpty ? "default" : "large")")
        app.buttons["home-message-c5"].tap()
        XCTAssertTrue(app.staticTexts["message-question"].appears(timeout: 5))
        XCTAssertTrue(choice.label.contains("更大的色块能突出每条公告。"))
        XCTAssertTrue(app.staticTexts["更小的格子能同时放下更多公告。"].firstMatch.exists)
        keepScreenshot("descriptions-detail-\(style)-\(arguments.isEmpty ? "default" : "large")")
    }

    private func keepScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testMetadataAndDetailRhythmLight() { verifyMetadataAndDetailRhythm(style: "Light") }
    func testMetadataAndDetailRhythmDark() { verifyMetadataAndDetailRhythm(style: "Dark") }
    func testMetadataAndDetailRhythmChineseExtraLarge() {
        verifyMetadataAndDetailRhythm(style: "Light", large: true)
    }

    private func verifyMetadataAndDetailRhythm(style: String, large: Bool = false) {
        launch(arguments: ["-AppleInterfaceStyle", style] + (large ? Self.accessibilityXXXL : []))
        let row = app.buttons["home-message-c5"]
        XCTAssertTrue(row.appears(timeout: 10))
        for _ in 0..<8 where !row.isHittable { app.swipeUp() }
        let project = row.staticTexts["prod-release"]
        XCTAssertTrue(project.exists, "Project must have its own untruncated text view")
        XCTAssertGreaterThan(project.frame.width, 70)
        let branchAndAgent = (large ? "" : "· ") + "release/v2.4 · worker-design"
        XCTAssertTrue(row.staticTexts[branchAndAgent].exists)
        keepScreenshot("round2-today-\(style)-\(large ? "AX" : "standard")")
        row.tap()
        XCTAssertTrue(app.staticTexts["message-question"].appears(timeout: 5))
        let facts = app.descendants(matching: .any)["decision-facts"].firstMatch
        let notice = timing("c5")
        if !large {
            XCTAssertTrue(notice.exists)
            let gap = notice.frame.minY - facts.frame.maxY
            // The notice text is inset 16 points inside its background card.
            XCTAssertEqual(gap, 28, accuracy: 2, "Visible blocks use one 12-point Space.s gap")
        }
        keepScreenshot("round2-detail-\(style)-\(large ? "AX" : "standard")")
    }

    private func assertFullWidth(_ first: String, _ second: String) {
        let top = app.buttons[first].frame
        let bottom = app.buttons[second].frame
        XCTAssertGreaterThanOrEqual(top.width, app.frame.width * 0.7)
        XCTAssertEqual(top.minX, bottom.minX, accuracy: 2)
        XCTAssertGreaterThanOrEqual(bottom.minY, top.maxY)
        XCTAssertGreaterThanOrEqual(top.height, 44)
        XCTAssertGreaterThanOrEqual(bottom.height, 44)
    }

    private func assertSideBySide(_ first: String, _ second: String, allowsWrapping: Bool = false) {
        let left = app.buttons[first].frame
        let right = app.buttons[second].frame
        XCTAssertGreaterThanOrEqual(left.width, 44)
        XCTAssertGreaterThanOrEqual(right.width, 44)
        XCTAssertGreaterThanOrEqual(left.height, 44)
        XCTAssertGreaterThanOrEqual(right.height, 44)
        if allowsWrapping && abs(left.midY - right.midY) > 2 {
            XCTAssertGreaterThanOrEqual(right.minY, left.maxY, "wrapped choices do not overlap")
            XCTAssertEqual(left.minX, right.minX, accuracy: 2, "wrapped rows share the leading edge")
        } else {
            XCTAssertEqual(left.midY, right.midY, accuracy: 2, "two choices share the same row")
            XCTAssertEqual(left.height, right.height, accuracy: 1, "two choices share the row height")
            XCTAssertLessThanOrEqual(left.maxX, right.minX, "choice buttons do not overlap")
        }
        XCTAssertGreaterThanOrEqual(left.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(left.maxX, app.frame.maxX)
        XCTAssertGreaterThanOrEqual(right.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(right.maxX, app.frame.maxX)
    }

    private func assertNoPanelControls() {
        // Give the panel load a moment to finish so an empty wall would have rendered.
        _ = app.staticTexts["实时面板"].appears(timeout: 2)
        XCTAssertFalse(app.staticTexts["实时面板"].exists, "no panels header without tiles")
        XCTAssertEqual(app.segmentedControls.count, 0, "no panel filter without tiles")
        XCTAssertFalse(app.buttons["刷新"].exists)
        XCTAssertFalse(app.buttons["Refresh"].exists)
    }
}
