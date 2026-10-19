// Covers remembered styles, combined filters, media paging, unified detail and confirmed row actions.
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
        XCTAssertTrue(app.tabBars.buttons["Box"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Box"].tap()
        XCTAssertTrue(app.buttons["box-item-demo-image"].waitForExistence(timeout: 10))
        setStyle("List")
    }

    func testCardsHaveContentEqualColumnsAndStyleSurvivesRelaunch() {
        setStyle("Cards")
        let agent = app.buttons["box-item-demo-agent-text"]
        let image = app.buttons["box-item-demo-image"]
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        XCTAssertTrue(agent.label.contains("Agent research notes"))
        XCTAssertEqual(agent.frame.width, image.frame.width, accuracy: 2)
        XCTAssertEqual(agent.frame.height, image.frame.height, accuracy: 2)
        XCTAssertLessThanOrEqual(agent.frame.maxX, image.frame.minX)
        let text = app.buttons["box-item-demo-text"]
        let link = app.buttons["box-item-demo-link"]
        XCTAssertTrue(text.label.contains("A passage to keep"))
        XCTAssertTrue(link.label.contains("developer.apple.com"))
        app.terminate()
        app.launchConfiguredDemo()
        app.tabBars.buttons["Box"].tap()
        XCTAssertEqual(app.buttons["box-style-menu"].value as? String, "Cards")
        setStyle("List")
    }

    func testTextDetailShowsContentOnceOmitsEmptyFieldsAndKeepsActionsInToolbar() {
        app.buttons["box-item-demo-agent-text"].tap()
        XCTAssertTrue(app.scrollViews["box-detail"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.alerts["Delete Agent research notes?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Cancel"].tap()
    }

    func testRowsUseTheSameHeightWithAndWithoutSummary() {
        let agent = app.buttons["box-item-demo-agent-text"]
        let image = app.buttons["box-item-demo-image"]
        let text = app.buttons["box-item-demo-text"]
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        XCTAssertEqual(agent.frame.height, image.frame.height, accuracy: 2)
        XCTAssertEqual(image.frame.height, text.frame.height, accuracy: 2)
        XCTAssertEqual(agent.frame.minX, image.frame.minX, accuracy: 2)
        XCTAssertLessThanOrEqual(agent.frame.maxY, image.frame.minY)
    }

    func testImageGridHasThreeSquareColumnsInEitherStyleAndCombinesAuthorFilters() {
        setFilter("image")
        assertThreeColumns()
        setStyle("Cards")
        assertThreeColumns()
        setAuthor("Agents")
        XCTAssertTrue(app.buttons["box-item-demo-grid-3"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["box-item-demo-image"].exists)
        setFilter("text")
        XCTAssertTrue(app.buttons["box-item-demo-agent-text"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["box-item-demo-text"].exists)
        setAuthor("Me")
        XCTAssertTrue(app.buttons["box-item-demo-text"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["box-item-demo-agent-text"].exists)
        XCTAssertTrue(app.buttons["box-filter-text"].isSelected)
        setStyle("List")
    }

    func testViewerPagesFilteredSetShowsActionsAndInfoThenConfirmsDeletion() {
        setFilter("image")
        setAuthor("Me")
        app.buttons["box-item-demo-grid-1"].tap()
        XCTAssertTrue(app.buttons["media-viewer-close"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["media-viewer-counter"].label, "2 / 3")
        XCTAssertTrue(app.staticTexts["Visual reference 1"].exists)
        app.buttons["media-viewer-copy"].tap()
        app.buttons["media-viewer-info"].tap()
        XCTAssertTrue(app.scrollViews["box-detail"].waitForExistence(timeout: 5))
        assertDetailValue("Format and size, image/png · 1 KB")
        app.buttons["Done"].tap()
        mediaZoomScroll(app).swipeRight()
        XCTAssertEqual(app.staticTexts["media-viewer-counter"].label, "1 / 3")
        assertMediaPinchZoom(app)
        mediaZoomScroll(app).doubleTap()
        app.buttons["media-viewer-delete"].tap()
        let alert = app.alerts["Delete Layout reference?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["Agents will no longer be able to read this item."].exists)
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["media-viewer-close"].exists)
        app.buttons["media-viewer-delete"].tap()
        app.alerts.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["media-viewer-close"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["box-item-demo-image"].exists)
    }

    func testVideosUseThreeSquareColumnsEvenWhenCardsAreSelected() {
        setFilter("video")
        setStyle("Cards")
        let first = app.buttons["box-item-demo-video"]
        let second = app.buttons["box-item-demo-grid-4"]
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        let tile = first.frame.height
        XCTAssertEqual(tile, 118, accuracy: 2)
        XCTAssertEqual(second.frame.height, tile, accuracy: 2)
        XCTAssertEqual(second.frame.minY, first.frame.minY, accuracy: 2)
        XCTAssertGreaterThan(second.frame.midX, first.frame.midX)
        first.tap()
        XCTAssertTrue(app.descendants(matching: .any)["media-viewer-video"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["media-viewer-counter"].label, "1 / 2")
        app.buttons["media-viewer-close"].tap()
        setStyle("List")
    }

    func testSwipeDeleteConfirmsAndLeadingShareUsesNativeSheet() {
        let row = app.buttons["box-item-demo-agent-text"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.alerts["Delete Agent research notes?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(row.exists)
        row.swipeRight()
        app.buttons["Share"].tap()
        XCTAssertTrue(app.cells["Copy"].waitForExistence(timeout: 5))
    }

    func testFailedMediaKeepsItsPageAndCanRetryWithActionsStillReachable() {
        app.terminate()
        app.configureDemoLaunch(["HIBOSS_DEMO_BOX_V2": "1",
                                 "HIBOSS_DEMO_BOX_MEDIA_FAILURE": "demo-grid-1"])
        app.launchConfiguredDemo()
        app.tabBars.buttons["Box"].tap()
        setFilter("image")
        XCTAssertTrue(app.buttons["box-item-demo-grid-1"].waitForExistence(timeout: 10))
        app.buttons["box-item-demo-grid-1"].tap()
        XCTAssertTrue(app.buttons["media-viewer-close"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["media-viewer-counter"].label, "2 / 4")
        let retry = app.buttons["Retry"].firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["media-viewer-copy"].isEnabled)
        XCTAssertFalse(app.buttons["media-viewer-share"].isEnabled)
        XCTAssertTrue(app.buttons["media-viewer-info"].isHittable)
        retry.tap()
        XCTAssertTrue(retry.waitForNonExistence(timeout: 5))
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
        XCTAssertTrue(app.buttons["media-viewer-delete"].waitForExistence(timeout: 10))
        app.buttons["media-viewer-delete"].tap()
        XCTAssertTrue(app.alerts["Delete Reference.png?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["media-viewer-close"].exists)
        app.buttons["media-viewer-delete"].tap()
        app.alerts.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["box-style-menu"].waitForExistence(timeout: 5))
        XCTAssertFalse(file.exists)
    }

    func testLinkAndTextUseSameDetailFieldsAndNoteCanBeEdited() {
        let link = app.buttons["box-item-demo-link"]
        for _ in 0..<5 where !link.isHittable { app.swipeUp() }
        link.tap()
        XCTAssertTrue(app.scrollViews["box-detail"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        draft.tap()
        draft.typeText("Saved link context")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["Saved link context"].waitForExistence(timeout: 5))
        let delete = app.buttons["Delete"]
        for _ in 0..<5 where !delete.isHittable { app.swipeUp() }
        delete.tap()
        XCTAssertTrue(app.alerts["Delete Apple Developer?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Cancel"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        let text = app.buttons["box-item-demo-text"]
        for _ in 0..<5 where !text.isHittable { app.swipeDown() }
        text.tap()
        XCTAssertTrue(app.scrollViews["box-detail"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Author"].exists)
        XCTAssertFalse(app.buttons["Open"].exists)
    }

    private func setStyle(_ title: String) {
        let menu = app.buttons["box-style-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        let choice = app.buttons[title]
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.tap()
        XCTAssertEqual(menu.value as? String, title)
    }

    func setFilter(_ rawValue: String) {
        if rawValue == "video" {
            XCTAssertTrue(app.buttons["box-item-demo-video"].waitForExistence(timeout: 10))
        } else if rawValue == "image" {
            XCTAssertTrue(app.buttons["box-item-demo-image"].waitForExistence(timeout: 10))
        }
        let filter = app.buttons["box-filter-\(rawValue)"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        let chips = app.scrollViews.containing(.button, identifier: "box-filter-liked").firstMatch
        for _ in 0..<3 where !filter.isHittable {
            if rawValue == "all" { chips.swipeRight() } else { chips.swipeLeft() }
        }
        XCTAssertTrue(filter.isHittable)
        filter.tap()
        XCTAssertTrue(filter.isSelected)
        if rawValue == "image" || rawValue == "video" {
            XCTAssertTrue(app.descendants(matching: .any)["box-photo-grid"].waitForExistence(timeout: 5))
        }
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

    private func setAuthor(_ title: String) {
        app.buttons["box-author-menu"].tap()
        app.buttons[title].tap()
    }

    private func assertThreeColumns() {
        let grid = app.descendants(matching: .any)["box-photo-grid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        let first = grid.buttons["box-item-demo-image"]
        let second = grid.buttons["box-item-demo-grid-1"]
        let third = grid.buttons["box-item-demo-grid-2"]
        XCTAssertTrue(third.waitForExistence(timeout: 5))
        let tile = first.frame.height
        XCTAssertEqual(tile, 118, accuracy: 2)
        XCTAssertEqual(second.frame.height, tile, accuracy: 2)
        XCTAssertEqual(third.frame.height, tile, accuracy: 2)
        XCTAssertEqual(third.frame.minY, first.frame.minY, accuracy: 2)
        XCTAssertEqual(second.frame.midX - first.frame.midX, tile + 8, accuracy: 2)
        XCTAssertEqual(third.frame.midX - second.frame.midX, tile + 8, accuracy: 2)
        XCTAssertLessThanOrEqual(third.frame.midX, app.frame.maxX)
    }
}
