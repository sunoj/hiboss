// Covers grid layout, combined filters, media paging, unified detail and confirmed row actions.
// Exports BoxV2UITests, using the same demo service boundaries as the production Box browser.
// Dependencies: XCTest, DemoLaunchSupport and MediaViewerTestSupport.

import XCTest

final class BoxV2UITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.configureDemoLaunch(["HIBOSS_DEMO_BOX_V2": "1"])
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchConfiguredDemo()
        XCTAssertTrue(app.tabBars.buttons["Box"].appears(timeout: 10))
        app.tabBars.buttons["Box"].tap()
        XCTAssertTrue(app.buttons["box-item-demo-image"].appears(timeout: 10))
    }

    func testTilesHaveContentAndEqualColumnsAcrossRelaunch() {
        let agent = app.buttons["box-item-demo-agent-text"]
        let image = app.buttons["box-item-demo-image"]
        XCTAssertTrue(image.appears(timeout: 5))
        XCTAssertTrue(agent.label.contains("Agent research notes"))
        XCTAssertEqual(agent.frame.width, image.frame.width, accuracy: 2)
        XCTAssertEqual(agent.frame.height, image.frame.height, accuracy: 2)
        XCTAssertLessThanOrEqual(agent.frame.maxX, image.frame.minX)
        let text = app.buttons["box-item-demo-text"]
        let link = app.buttons["box-item-demo-link"]
        app.revealBoxTile(text)
        XCTAssertTrue(text.label.contains("A passage to keep"))
        XCTAssertTrue(link.label.contains("docs.example.com"))
        app.terminate()
        app.launchConfiguredDemo()
        app.tabBars.buttons["Box"].tap()
        XCTAssertTrue(image.appears(timeout: 5))
        XCTAssertLessThanOrEqual(agent.frame.maxX, image.frame.minX)
    }

    func testTextDetailShowsContentOnceOmitsEmptyFieldsAndKeepsActionsInToolbar() {
        app.buttons["box-item-demo-agent-text"].tap()
        XCTAssertTrue(app.scrollViews["box-detail"].appears(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "Agent research notes").count, 1)
        XCTAssertFalse(app.staticTexts["Tags"].exists)
        XCTAssertFalse(app.staticTexts["None"].exists)
        let copy = app.buttons["Copy"]
        let edit = app.buttons["Edit note"]
        let delete = app.buttons["Delete"]
        // System toolbar items own their hit area; assert reachability, not visual height.
        for button in [copy, edit, delete] { XCTAssertTrue(button.isHittable) }
        XCTAssertEqual(copy.frame.midY, edit.frame.midY, accuracy: 2)
        XCTAssertEqual(edit.frame.midY, delete.frame.midY, accuracy: 2)
        delete.tap()
        XCTAssertTrue(app.alerts["Delete Agent research notes?"].appears(timeout: 5))
        app.alerts.buttons["Cancel"].tap()
    }

    func testTilesUseTheSameHeightWithAndWithoutSummary() {
        let agent = app.buttons["box-item-demo-agent-text"]
        let image = app.buttons["box-item-demo-image"]
        let text = app.buttons["box-item-demo-text"]
        XCTAssertTrue(image.appears(timeout: 5))
        XCTAssertEqual(agent.frame.height, image.frame.height, accuracy: 2)
        XCTAssertEqual(image.frame.height, text.frame.height, accuracy: 2)
        XCTAssertEqual(agent.frame.minY, image.frame.minY, accuracy: 2)
        XCTAssertLessThanOrEqual(agent.frame.maxX, image.frame.minX)
        XCTAssertLessThanOrEqual(agent.frame.maxY, text.frame.minY)
    }

    func testImageGridHasTwoColumnsAndCombinesAuthorFilters() {
        setFilter("image")
        assertTwoColumns()
        setAuthor("agents")
        XCTAssertTrue(app.buttons["box-item-demo-grid-3"].appears(timeout: 5))
        XCTAssertFalse(app.buttons["box-item-demo-image"].exists)
        setFilter("text")
        XCTAssertTrue(app.buttons["box-item-demo-agent-text"].appears(timeout: 5))
        XCTAssertFalse(app.buttons["box-item-demo-text"].exists)
        setAuthor("mine")
        XCTAssertTrue(app.buttons["box-item-demo-text"].appears(timeout: 5))
        XCTAssertFalse(app.buttons["box-item-demo-agent-text"].exists)
        XCTAssertTrue(app.buttons["box-filter-text"].isSelected)
    }

    func testViewerPagesFilteredSetShowsActionsAndInfoThenConfirmsDeletion() {
        setFilter("image")
        setAuthor("mine")
        let tile = app.buttons["box-item-demo-grid-1"]
        app.revealBoxTile(tile)
        tile.tap()
        XCTAssertTrue(app.buttons["media-viewer-close"].appears(timeout: 10))
        XCTAssertEqual(app.staticTexts["media-viewer-counter"].label, "2 / 3")
        XCTAssertTrue(app.staticTexts["Visual reference 1"].exists)
        app.buttons["media-viewer-copy"].tap()
        app.buttons["media-viewer-info"].tap()
        XCTAssertTrue(app.scrollViews["box-detail"].appears(timeout: 5))
        assertDetailValue("Format and size, image/png · 1 KB")
        app.buttons["Done"].tap()
        mediaZoomScroll(app).swipeRight()
        XCTAssertEqual(app.staticTexts["media-viewer-counter"].label, "1 / 3")
        assertMediaPinchZoom(app)
        mediaZoomScroll(app).doubleTap()
        app.buttons["media-viewer-delete"].tap()
        let alert = app.alerts["Delete Layout reference?"]
        XCTAssertTrue(alert.appears(timeout: 5))
        XCTAssertTrue(alert.staticTexts["Agents will no longer be able to read this item."].exists)
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["media-viewer-close"].exists)
        app.buttons["media-viewer-delete"].tap()
        app.alerts.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["media-viewer-close"].disappears(timeout: 5))
        XCTAssertFalse(app.buttons["box-item-demo-image"].exists)
    }

    func testVideosUseTwoColumns() {
        setFilter("video")
        let first = app.buttons["box-item-demo-video"]
        let second = app.buttons["box-item-demo-grid-4"]
        XCTAssertTrue(second.appears(timeout: 5))
        let tile = first.frame.height
        XCTAssertGreaterThanOrEqual(tile, 44)
        XCTAssertEqual(first.frame.width, second.frame.width, accuracy: 2)
        XCTAssertEqual(second.frame.height, tile, accuracy: 2)
        XCTAssertEqual(second.frame.minY, first.frame.minY, accuracy: 2)
        XCTAssertGreaterThan(second.frame.midX, first.frame.midX)
        first.tap()
        XCTAssertTrue(app.descendants(matching: .any)["media-viewer-video"].appears(timeout: 10))
        XCTAssertEqual(app.staticTexts["media-viewer-counter"].label, "1 / 2")
        app.buttons["media-viewer-close"].tap()
    }

    func testTileMenuDeleteConfirmsAndShareUsesNativeSheet() {
        let row = app.buttons["box-item-demo-agent-text"]
        XCTAssertTrue(row.appears(timeout: 5))
        row.press(forDuration: 1)
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.alerts["Delete Agent research notes?"].appears(timeout: 5))
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(row.exists)
        row.press(forDuration: 1)
        app.buttons["Share"].tap()
        XCTAssertTrue(app.cells["Copy"].appears(timeout: 5))
    }

    func testFailedMediaKeepsItsPageAndCanRetryWithActionsStillReachable() {
        app.terminate()
        app.configureDemoLaunch(["HIBOSS_DEMO_BOX_V2": "1",
                                 "HIBOSS_DEMO_BOX_MEDIA_FAILURE": "demo-grid-1"])
        app.launchConfiguredDemo()
        app.tabBars.buttons["Box"].tap()
        setFilter("image")
        XCTAssertTrue(app.buttons["box-item-demo-grid-1"].appears(timeout: 10))
        let tile = app.buttons["box-item-demo-grid-1"]
        app.revealBoxTile(tile)
        tile.tap()
        XCTAssertTrue(app.buttons["media-viewer-close"].appears(timeout: 10))
        XCTAssertEqual(app.staticTexts["media-viewer-counter"].label, "2 / 4")
        let retry = app.buttons["Retry"].firstMatch
        XCTAssertTrue(retry.appears(timeout: 5))
        XCTAssertFalse(app.buttons["media-viewer-copy"].isEnabled)
        XCTAssertFalse(app.buttons["media-viewer-share"].isEnabled)
        XCTAssertTrue(app.buttons["media-viewer-info"].isHittable)
        retry.tap()
        XCTAssertTrue(retry.disappears(timeout: 5))
        XCTAssertTrue(app.buttons["media-viewer-copy"].isEnabled)
        XCTAssertEqual(app.staticTexts["media-viewer-counter"].label, "2 / 4")
        assertMediaPinchZoom(app)
    }

    func testFileImageViewerDeleteUsesTheSameConfirmation() {
        app.terminate()
        app.configureDemoLaunch(["HIBOSS_DEMO_BOX_FILE": "image"])
        app.launchConfiguredDemo()
        app.tabBars.buttons["Box"].tap()
        let file = app.buttons["box-item-demo-file"]
        for _ in 0..<5 where !file.isHittable { app.swipeUp() }
        file.tap()
        let open = app.buttons["Open file"]
        for _ in 0..<5 where !open.isHittable { app.swipeUp() }
        open.tap()
        XCTAssertTrue(app.buttons["media-viewer-delete"].appears(timeout: 10))
        app.buttons["media-viewer-delete"].tap()
        XCTAssertTrue(app.alerts["Delete Reference.png?"].appears(timeout: 5))
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["media-viewer-close"].exists)
        app.buttons["media-viewer-delete"].tap()
        app.alerts.buttons["Delete"].tap()
        XCTAssertTrue(app.scrollViews["box-grid"].appears(timeout: 5))
        XCTAssertFalse(file.exists)
    }

    func testLinkAndTextUseSameDetailFieldsAndNoteCanBeEdited() {
        let link = app.buttons["box-item-demo-link"]
        for _ in 0..<5 where !link.isHittable { app.swipeUp() }
        link.tap()
        XCTAssertTrue(app.scrollViews["box-detail"].appears(timeout: 5))
        for field in ["Author", "Project", "Tags", "Format and size", "Added"] {
            XCTAssertTrue(app.staticTexts[field].exists, field)
        }
        assertDetailValue("Author, Me")
        assertDetailValue("Tags, reference")
        let edit = app.buttons["Edit note"]
        for _ in 0..<5 where !edit.isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["Open"].exists)
        edit.tap()
        let draft = app.textViews["box-note-draft"]
        XCTAssertTrue(draft.appears(timeout: 5))
        draft.tap()
        draft.typeText("Saved link context")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["Saved link context"].appears(timeout: 5))
        let delete = app.buttons["Delete"]
        for _ in 0..<5 where !delete.isHittable { app.swipeUp() }
        delete.tap()
        XCTAssertTrue(app.alerts["Delete API style guide?"].appears(timeout: 5))
        app.alerts.buttons["Cancel"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        let text = app.buttons["box-item-demo-text"]
        for _ in 0..<5 where !text.isHittable { app.swipeDown() }
        text.tap()
        XCTAssertTrue(app.scrollViews["box-detail"].appears(timeout: 5))
        XCTAssertTrue(app.staticTexts["Author"].exists)
        XCTAssertFalse(app.buttons["Open"].exists)
    }

    func setFilter(_ rawValue: String) {
        app.tapBoxChip("box-filter-\(rawValue)")
    }

    private func assertDetailValue(_ expected: String) {
        let group = app.descendants(matching: .any)["box-detail-information"]
        let value = group.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@ OR value == %@", expected, expected)).firstMatch
        for _ in 0..<5 where !value.exists { app.scrollViews["box-detail"].swipeUp() }
        if !value.exists {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "box-detail-missing-value"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        XCTAssertTrue(value.exists, app.debugDescription)
    }

    private func setAuthor(_ author: String) {
        app.tapBoxChip("box-author-\(author)")
    }

    private func assertTwoColumns() {
        let grid = app.scrollViews["box-grid"]
        let first = grid.buttons["box-item-demo-image"]
        let second = grid.buttons["box-item-demo-grid-1"]
        let third = grid.buttons["box-item-demo-grid-2"]
        XCTAssertTrue(first.appears(timeout: 5))
        XCTAssertTrue(second.exists)
        XCTAssertEqual(first.frame.width, second.frame.width, accuracy: 2)
        XCTAssertEqual(first.frame.minY, second.frame.minY, accuracy: 2)
        XCTAssertLessThanOrEqual(first.frame.maxX, second.frame.minX)
        app.revealBoxTile(third)
        XCTAssertEqual(first.frame.minX, third.frame.minX, accuracy: 2)
    }
}

extension XCUIApplication {
    func tapBoxChip(_ identifier: String) {
        let chip = buttons[identifier]
        let row = scrollViews["box-filters"]
        XCTAssertTrue(row.appears(timeout: 5))
        for _ in 0..<8 {
            let frame = chip.exists ? chip.frame : .null
            if !frame.isEmpty && row.frame.contains(frame) {
                XCTAssertTrue(chip.isHittable, identifier)
                chip.tap()
                XCTAssertTrue(chip.isSelected, identifier)
                return
            }
            if !frame.isEmpty && frame.midX < row.frame.midX { row.swipeRight() }
            else { row.swipeLeft() }
        }
        XCTFail("Box chip did not scroll into view: \(identifier)")
    }

    func revealBoxTile(_ tile: XCUIElement) {
        let grid = scrollViews["box-grid"]
        XCTAssertTrue(grid.appears(timeout: 5))
        for _ in 0..<12 {
            let frame = tile.exists ? tile.frame : .null
            if !frame.isEmpty && grid.frame.contains(frame) && tile.isHittable { return }
            if !frame.isEmpty && frame.minY < grid.frame.minY { grid.swipeDown() }
            else { grid.swipeUp() }
        }
        XCTFail("Box tile did not scroll into view: \(tile.identifier)")
    }
}
