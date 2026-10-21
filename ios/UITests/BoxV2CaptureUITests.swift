// Captures Box list, cards, grid, unified detail and viewer in localized appearance variants.
// Exports BoxV2CaptureUITests with retained screenshot attachments and geometry assertions.
// Dependencies: XCTest and launchConfiguredDemo on the assigned iPhone simulator.

import XCTest

final class BoxV2CaptureUITests: XCTestCase {
    func testChineseLightScreens() { capture(language: "zh-Hans", appearance: "Light") }
    func testEnglishLightScreens() { capture(language: "en", appearance: "Light") }
    func testChineseDarkScreens() { capture(language: "zh-Hans", appearance: "Dark") }
    func testChineseLargeTextScreens() { capture(language: "zh-Hans", appearance: "Light", large: true) }

    private func capture(language: String, appearance: String, large: Bool = false) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.configureDemoLaunch(["HIBOSS_DEMO_BOX_V2": "1"])
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", language,
                               "-AppleInterfaceStyle", appearance]
        if large {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName",
                                    "UICTContentSizeCategoryAccessibilityL"]
        }
        app.launchConfiguredDemo()
        XCTAssertTrue(app.tabBars.buttons.element(boundBy: 2).waitForExistence(timeout: 10))
        app.tabBars.buttons.element(boundBy: 2).tap()
        let locale = language == "en" ? "en" : "zh"
        let prefix = "\(locale)-box-v2-\(appearance.lowercased())\(large ? "-ax" : "")"
        setStyle(app, language == "en" ? "List" : "列表")
        XCTAssertTrue(app.buttons["box-item-demo-image"].waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(app.buttons["box-item-demo-agent-text"].frame.maxX, app.frame.maxX)
        if language == "zh-Hans" {
            XCTAssertFalse(app.buttons["box-item-demo-agent-text"].label.contains("秒钟"))
        }
        shot(app, "\(prefix)-list")
        setStyle(app, language == "en" ? "Cards" : "卡片")
        shot(app, "\(prefix)-cards")
        setStyle(app, language == "en" ? "List" : "列表")
        app.buttons["box-item-demo-agent-text"].tap()
        XCTAssertTrue(app.scrollViews["box-detail"].waitForExistence(timeout: 5))
        shot(app, "\(prefix)-detail")
        if large { captureDetailActions(app, prefix: prefix, language: language) }
        detailDelete(app, language: language).tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        shot(app, "\(prefix)-delete-confirmation")
        app.alerts.buttons[language == "en" ? "Cancel" : "取消"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        captureMediaAndMenus(app, prefix: prefix, language: language)
        app.terminate()
    }

    private func captureMediaAndMenus(_ app: XCUIApplication, prefix: String, language: String) {
        tapFilter(app, identifier: "box-filter-image")
        XCTAssertTrue(app.buttons["box-item-demo-grid-2"].waitForExistence(timeout: 10))
        shot(app, "\(prefix)-grid")
        app.buttons["box-item-demo-image"].tap()
        XCTAssertTrue(app.buttons["media-viewer-close"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.images["media-viewer-image"].waitForExistence(timeout: 10))
        for id in ["media-viewer-copy", "media-viewer-info", "media-viewer-delete"] {
            XCTAssertTrue(app.buttons[id].isHittable)
            XCTAssertGreaterThanOrEqual(app.buttons[id].frame.height, 44)
        }
        shot(app, "\(prefix)-viewer")
        app.buttons["media-viewer-close"].tap()
        assertMenuTarget(app, identifier: "box-author-menu", option: language == "en" ? "All" : "全部",
                         captureName: "\(prefix)-author-menu")
        assertMenuTarget(app, identifier: "box-style-menu", option: language == "en" ? "List" : "列表",
                         captureName: "\(prefix)-style-menu")
    }

    private func tapFilter(_ app: XCUIApplication, identifier: String) {
        let chip = app.buttons[identifier]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        let row = app.scrollViews.containing(.button, identifier: "box-filter-all").firstMatch
        XCTAssertTrue(row.exists)
        for _ in 0..<5 {
            if row.frame.contains(chip.frame) && chip.isHittable { break }
            if chip.frame.midX < row.frame.minX {
                row.swipeRight()
            } else {
                row.swipeLeft()
            }
        }
        XCTAssertTrue(chip.isHittable, identifier)
        chip.tap()
    }

    private func setStyle(_ app: XCUIApplication, _ label: String) {
        app.buttons["box-style-menu"].tap()
        app.buttons[label].tap()
    }

    private func captureDetailActions(_ app: XCUIApplication, prefix: String, language: String) {
        let direct = app.buttons[language == "en" ? "Delete" : "删除"].isHittable
        let delete = detailDelete(app, language: language)
        shot(app, "\(prefix)-detail-actions")
        if !direct {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
            XCTAssertFalse(delete.isHittable)
        }
    }

    private func detailDelete(_ app: XCUIApplication, language: String) -> XCUIElement {
        let delete = app.buttons[language == "en" ? "Delete" : "删除"]
        if !delete.isHittable {
            let overflow = app.toolbars.buttons.matching(NSPredicate(
                format: "label IN %@", ["More", "更多"])).firstMatch
            XCTAssertTrue(overflow.isHittable)
            overflow.tap()
        }
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        XCTAssertTrue(delete.isHittable)
        return delete
    }

    private func assertMenuTarget(
        _ app: XCUIApplication, identifier: String, option: String, captureName: String
    ) {
        // A native toolbar Menu owns its hit area; open it once and pick the option.
        let button = app.buttons[identifier]
        XCTAssertTrue(button.isHittable, identifier)
        let choice = app.buttons.matching(NSPredicate(
            format: "label == %@ AND identifier != %@", option, "box-filter-all")).firstMatch
        button.tap()
        XCTAssertTrue(choice.waitForExistence(timeout: 3), identifier)
        shot(app, captureName)
        choice.tap()
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}

extension BoxV2UITests {
    func testImageAndVideoTilesHaveDisjointFramesAndEdgeTapsOpenOwnItems() {
        assertMediaTiles(
            filter: "image",
            tiles: [
                ("demo-image", "Layout reference"),
                ("demo-grid-1", "Visual reference 1"),
                ("demo-grid-2", "Visual reference 2"),
                ("demo-grid-3", "Visual reference 3"),
            ])
        setFilter("all")
        assertMediaTiles(
            filter: "video",
            tiles: [
                ("demo-video", "Motion reference"),
                ("demo-grid-4", "Visual reference 4"),
            ])
    }

    private func assertMediaTiles(filter: String, tiles: [(String, String)]) {
        setFilter(filter)
        let grid = app.descendants(matching: .any)["box-photo-grid"]
        let expectedWidth = (app.frame.width - 48) / 3
        let frames = tiles.map { tile in
            let button = grid.buttons["box-item-\(tile.0)"]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            XCTAssertEqual(button.frame.width, expectedWidth, accuracy: 2, tile.0)
            XCTAssertEqual(button.frame.height, expectedWidth, accuracy: 2, tile.0)
            return (button.frame, tile.1)
        }
        for (index, frame) in frames.enumerated() {
            for other in frames.dropFirst(index + 1) {
                XCTAssertFalse(frame.0.intersects(other.0), "\(frame.1) overlaps \(other.1)")
            }
        }
        for (frame, title) in frames {
            tapInsideEdges(of: frame, size: expectedWidth, title: title)
            XCTAssertTrue(grid.waitForExistence(timeout: 5))
        }
    }

    private func tapInsideEdges(of frame: CGRect, size: CGFloat, title: String) {
        let cell = CGRect(x: frame.midX - size / 2, y: frame.midY - size / 2,
                          width: size, height: size)
        for point in [
            CGPoint(x: cell.minX + 2, y: cell.midY),
            CGPoint(x: cell.maxX - 2, y: cell.midY),
            CGPoint(x: cell.midX, y: cell.minY + 2),
            CGPoint(x: cell.midX, y: cell.maxY - 2),
        ] {
            app.coordinate(withNormalizedOffset: CGVector(
                dx: point.x / app.frame.width, dy: point.y / app.frame.height)).tap()
            XCTAssertTrue(app.buttons["media-viewer-close"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5), title)
            app.buttons["media-viewer-close"].tap()
        }
    }
}

// Regresses grid swipe isolation and equal card surfaces using mixed demo content.
// Keeps list actions and context menus covered alongside light/dark card captures.
final class BoxCardSwipeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.configureDemoLaunch(["HIBOSS_DEMO_BOX_V2": "1"])
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    func testCardsIgnoreHorizontalSwipesAndKeepContextActions() {
        openBox(style: "Cards")
        let card = app.buttons["box-item-demo-agent-text"]
        let neighbor = app.buttons["box-item-demo-image"]
        assertSwipesKeepGrid(card, neighbor: neighbor, gridID: "box-cards")
        card.tap()
        XCTAssertTrue(app.scrollViews["box-detail"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        card.press(forDuration: 1)
        for title in ["Like", "Share", "Add to Collection…", "Delete"] {
            XCTAssertTrue(app.buttons[title].exists, title)
        }
    }

    func testMediaGridIgnoresHorizontalSwipesInListStyle() {
        openBox(style: "List")
        app.buttons["box-filter-image"].tap()
        let card = app.buttons["box-item-demo-image"]
        let neighbor = app.buttons["box-item-demo-grid-1"]
        XCTAssertTrue(neighbor.waitForExistence(timeout: 5))
        assertSwipesKeepGrid(card, neighbor: neighbor, gridID: "box-photo-grid")
        card.tap()
        XCTAssertTrue(app.buttons["media-viewer-close"].waitForExistence(timeout: 5))
    }

    func testListRetainsTrailingDeleteAndLeadingLikeShare() {
        openBox(style: "List")
        let row = app.buttons["box-item-demo-agent-text"]
        row.swipeLeft()
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 3))
        row.swipeRight()
        row.swipeRight()
        XCTAssertTrue(app.buttons["Share"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Like"].exists)
    }

    func testMixedCardsLight() { captureCards(appearance: "Light") }
    func testMixedCardsDark() { captureCards(appearance: "Dark") }

    private func openBox(style: String) {
        app.launchConfiguredDemo()
        XCTAssertTrue(app.tabBars.buttons["Box"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Box"].tap()
        XCTAssertTrue(app.buttons["box-item-demo-image"].waitForExistence(timeout: 10))
        app.buttons["box-style-menu"].tap()
        app.buttons[style].tap()
        XCTAssertTrue(app.buttons["box-filter-all"].isSelected)
    }

    private func assertSwipesKeepGrid(
        _ card: XCUIElement, neighbor: XCUIElement, gridID: String
    ) {
        let original = card.frame
        let adjacent = neighbor.frame
        for left in [true, false] {
            let start = card.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.9 : 0.1, dy: 0.5))
            let end = card.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.1 : 0.9, dy: 0.5))
            start.press(forDuration: 0.1, thenDragTo: end)
            let detailOpened = app.scrollViews["box-detail"].exists
                || app.buttons["media-viewer-close"].exists
            let list = app.descendants(matching: .any)[gridID]
            let revealedActions = ["Delete", "Share", "Like"].flatMap { title in
                app.buttons.matching(NSPredicate(format: "label == %@", title)).allElementsBoundByIndex
            }.filter { $0.isHittable && list.frame.contains($0.frame) && !detailOpened }
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "grid-after-\(left ? "left" : "right")-swipe"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            XCTAssertTrue(revealedActions.isEmpty, "Swipe actions revealed inside the list")
            XCTAssertFalse(detailOpened, "A horizontal drag must not activate a card")
            XCTAssertEqual(card.frame.minX, original.minX, accuracy: 1)
            XCTAssertEqual(card.frame.minY, original.minY, accuracy: 1)
            XCTAssertEqual(neighbor.frame.minX, adjacent.minX, accuracy: 1)
            XCTAssertEqual(neighbor.frame.minY, adjacent.minY, accuracy: 1)
            XCTAssertTrue(card.isHittable)
            XCTAssertTrue(neighbor.isHittable)
        }
    }

    private func captureCards(appearance: String) {
        app.launchArguments += ["-AppleInterfaceStyle", appearance]
        openBox(style: "Cards")
        let link = app.buttons["box-item-demo-link"]
        let text = app.buttons["box-item-demo-text"]
        for _ in 0..<3 where !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.isHittable)
        XCTAssertTrue(text.isHittable)
        XCTAssertEqual(link.frame.minY, text.frame.minY, accuracy: 1)
        XCTAssertEqual(link.frame.height, 260, accuracy: 1)
        XCTAssertEqual(text.frame.height, link.frame.height, accuracy: 1)
        XCTAssertTrue(link.label.contains("developer.apple.com"))
        XCTAssertEqual(link.staticTexts["Apple Developer"].frame.minY, link.frame.minY + 66, accuracy: 2)
        XCTAssertEqual(text.staticTexts["A passage to keep"].frame.minY, text.frame.minY + 12, accuracy: 2)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "box-mixed-cards-\(appearance.lowercased())"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["box-style-menu"].tap()
        app.buttons["List"].tap()
    }
}
