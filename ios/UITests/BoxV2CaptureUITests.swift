// Captures the Box grid, tile menu, unified detail and viewer in localized appearance variants.
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
        XCTAssertTrue(app.tabBars.buttons.element(boundBy: 2).appears(timeout: 10))
        app.tabBars.buttons.element(boundBy: 2).tap()
        let locale = language == "en" ? "en" : "zh"
        let prefix = "\(locale)-box-v2-\(appearance.lowercased())\(large ? "-ax" : "")"
        let agent = app.buttons["box-item-demo-agent-text"]
        let image = app.buttons["box-item-demo-image"]
        app.revealBoxTile(agent)
        XCTAssertLessThanOrEqual(agent.frame.maxX, app.frame.maxX)
        if large {
            app.revealBoxTile(image)
            XCTAssertEqual(agent.frame.minX, image.frame.minX, accuracy: 2)
            XCTAssertLessThanOrEqual(agent.frame.maxY, image.frame.minY)
            app.revealBoxTile(agent)
        }
        if language == "zh-Hans" {
            XCTAssertFalse(app.buttons["box-item-demo-agent-text"].label.contains("秒钟"))
        }
        shot(app, "\(prefix)-grid")
        agent.press(forDuration: 1)
        XCTAssertTrue(app.buttons[language == "en" ? "Delete" : "删除"].appears(timeout: 5))
        shot(app, "\(prefix)-tile-menu")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        agent.tap()
        XCTAssertTrue(app.scrollViews["box-detail"].appears(timeout: 5))
        shot(app, "\(prefix)-detail")
        if large { captureDetailActions(app, prefix: prefix, language: language) }
        detailDelete(app, language: language).tap()
        XCTAssertTrue(app.alerts.firstMatch.appears(timeout: 5))
        shot(app, "\(prefix)-delete-confirmation")
        app.alerts.buttons[language == "en" ? "Cancel" : "取消"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        captureMedia(app, prefix: prefix)
        app.terminate()
    }

    private func captureMedia(_ app: XCUIApplication, prefix: String) {
        app.tapBoxChip("box-filter-image")
        let image = app.buttons["box-item-demo-image"]
        app.revealBoxTile(image)
        shot(app, "\(prefix)-images")
        image.tap()
        XCTAssertTrue(app.buttons["media-viewer-close"].appears(timeout: 10))
        XCTAssertTrue(app.images["media-viewer-image"].appears(timeout: 10))
        for id in ["media-viewer-copy", "media-viewer-info", "media-viewer-delete"] {
            XCTAssertTrue(app.buttons[id].isHittable)
            XCTAssertGreaterThanOrEqual(app.buttons[id].frame.height, 44)
        }
        shot(app, "\(prefix)-viewer")
        app.buttons["media-viewer-close"].tap()
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
        XCTAssertTrue(delete.appears(timeout: 3))
        XCTAssertTrue(delete.isHittable)
        return delete
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
        let grid = app.descendants(matching: .any)["box-grid"]
        let expectedWidth = (app.frame.width - 44) / 2
        let frames = tiles.map { tile in
            let button = grid.buttons["box-item-\(tile.0)"]
            XCTAssertTrue(button.appears(timeout: 5))
            XCTAssertEqual(button.frame.width, expectedWidth, accuracy: 2, tile.0)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, tile.0)
            return (button.frame, tile.1)
        }
        for (index, frame) in frames.enumerated() {
            for other in frames.dropFirst(index + 1) {
                XCTAssertFalse(frame.0.intersects(other.0), "\(frame.1) overlaps \(other.1)")
            }
        }
        for (id, title) in tiles {
            let tile = grid.buttons["box-item-\(id)"]
            app.revealBoxTile(tile)
            tapInsideEdges(of: tile.frame, title: title)
            XCTAssertTrue(grid.appears(timeout: 5))
        }
    }

    private func tapInsideEdges(of cell: CGRect, title: String) {
        for point in [
            CGPoint(x: cell.minX + 2, y: cell.midY),
            CGPoint(x: cell.maxX - 2, y: cell.midY),
            CGPoint(x: cell.midX, y: cell.minY + 2),
            CGPoint(x: cell.midX, y: cell.maxY - 2),
        ] {
            app.coordinate(withNormalizedOffset: CGVector(
                dx: point.x / app.frame.width, dy: point.y / app.frame.height)).tap()
            XCTAssertTrue(app.buttons["media-viewer-close"].appears(timeout: 5))
            XCTAssertTrue(app.staticTexts[title].appears(timeout: 5), title)
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
        openBox()
        let card = app.buttons["box-item-demo-agent-text"]
        let neighbor = app.buttons["box-item-demo-image"]
        assertSwipesKeepGrid(card, neighbor: neighbor, gridID: "box-grid")
        card.tap()
        XCTAssertTrue(app.scrollViews["box-detail"].appears(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        card.press(forDuration: 1)
        for title in ["Like", "Share", "Add to Collection…", "Delete"] {
            XCTAssertTrue(app.buttons[title].exists, title)
        }
    }

    func testMediaGridIgnoresHorizontalSwipes() {
        openBox()
        app.tapBoxChip("box-filter-image")
        let card = app.buttons["box-item-demo-image"]
        let neighbor = app.buttons["box-item-demo-grid-1"]
        XCTAssertTrue(neighbor.appears(timeout: 5))
        assertSwipesKeepGrid(card, neighbor: neighbor, gridID: "box-grid")
        card.tap()
        XCTAssertTrue(app.buttons["media-viewer-close"].appears(timeout: 5))
    }

    func testGridContextMenuKeepsDeleteLikeAndShare() {
        openBox()
        let tile = app.buttons["box-item-demo-agent-text"]
        tile.press(forDuration: 1)
        for action in ["Delete", "Share", "Like"] {
            XCTAssertTrue(app.buttons[action].appears(timeout: 3))
        }
    }

    func testMixedCardsLight() { captureCards(appearance: "Light") }
    func testMixedCardsDark() { captureCards(appearance: "Dark") }

    private func openBox() {
        app.launchConfiguredDemo()
        XCTAssertTrue(app.tabBars.buttons["Box"].appears(timeout: 10))
        app.tabBars.buttons["Box"].tap()
        XCTAssertTrue(app.buttons["box-item-demo-image"].appears(timeout: 10))
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
        openBox()
        let link = app.buttons["box-item-demo-link"]
        let text = app.buttons["box-item-demo-text"]
        for _ in 0..<3 where !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.isHittable)
        XCTAssertTrue(text.isHittable)
        XCTAssertEqual(link.frame.minY, text.frame.minY, accuracy: 1)
        XCTAssertEqual(text.frame.height, link.frame.height, accuracy: 1)
        XCTAssertTrue(link.label.contains("docs.example.com"))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "box-mixed-cards-\(appearance.lowercased())"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
