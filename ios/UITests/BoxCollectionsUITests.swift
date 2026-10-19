// End-to-end likes, collection management, membership and localized captures.
// Runs through the configured demo service and keeps screenshots as xcresult attachments.
import XCTest

final class BoxCollectionsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.configureDemoLaunch(["HIBOSS_DEMO_BOX_V2": "1"])
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchConfiguredDemo()
        app.tabBars.buttons["Box"].tap()
        XCTAssertTrue(app.buttons["box-item-demo-image"].waitForExistence(timeout: 10))
        app.buttons["box-style-menu"].tap()
        app.buttons["List"].tap()
    }

    func testLikedFilterDetailAndViewerHeart() {
        XCTAssertTrue(app.buttons["box-filter-liked"].isHittable)
        XCTAssertLessThan(app.buttons["box-filter-liked"].frame.minX,
                          app.buttons["box-filter-all"].frame.minX)
        app.buttons["box-filter-liked"].tap()
        XCTAssertTrue(app.buttons["box-filter-liked"].isSelected)
        XCTAssertFalse(app.buttons["box-item-demo-agent-text"].exists)
        capture("collections-liked-filter")
        app.buttons["box-item-demo-text"].tap()
        XCTAssertEqual(app.buttons["box-like"].label, "Unlike")
        app.buttons["box-like"].tap()
        XCTAssertEqual(app.buttons["box-like"].label, "Like")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertFalse(app.buttons["box-item-demo-text"].exists)
        app.buttons["box-item-demo-image"].tap()
        XCTAssertTrue(app.buttons["media-viewer-close"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["box-like"].label, "Unlike")
        app.buttons["box-like"].tap()
        XCTAssertEqual(app.buttons["box-like"].label, "Like")
    }

    func testGridScopedListAndImmediateMembershipChecklist() {
        XCTAssertTrue(app.navigationBars.buttons["box-collections"].isHittable)
        app.buttons["box-collections"].tap()
        let design = app.buttons["box-collection-demo-design"]
        XCTAssertTrue(design.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Collections"].exists)
        capture("collections-grid")
        design.tap()
        XCTAssertTrue(app.buttons["box-item-demo-image"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["box-item-demo-agent-text"].exists)
        capture("collections-scoped-list")
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        let row = app.buttons["box-item-demo-agent-text"]
        row.press(forDuration: 1)
        app.buttons["Add to Collection…"].tap()
        let membership = app.buttons["box-membership-demo-design"]
        XCTAssertTrue(membership.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Add to Collection"].exists)
        assertSelected(membership, false)
        membership.tap()
        assertSelected(membership, true)
        capture("collections-add-sheet")
        app.buttons["Done"].tap()
        row.tap()
        let collections = app.descendants(matching: .any)["box-detail-collections"]
        XCTAssertTrue(collections.waitForExistence(timeout: 5))
        XCTAssertTrue(collections.label.contains("Design references"))
        app.buttons["Add to Collection…"].tap()
        membership.tap()
        assertSelected(membership, false)
    }

    func testNewRenameDeleteKeepsItemsAndRejectsDuplicateNames() {
        app.buttons["box-collections"].tap()
        app.buttons["New Collection"].tap()
        let name = app.textFields["box-collection-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Reading")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["box-organization-error"].waitForExistence(timeout: 5))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 7) + "Trip")
        app.buttons["Save"].tap()
        let trip = app.buttons.containing(.staticText, identifier: "Trip").firstMatch
        XCTAssertTrue(trip.waitForExistence(timeout: 5))
        trip.press(forDuration: 1)
        app.buttons["Rename"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "Travel")
        app.buttons["Save"].tap()
        let travel = app.buttons.containing(.staticText, identifier: "Travel").firstMatch
        XCTAssertTrue(travel.waitForExistence(timeout: 5))
        travel.press(forDuration: 1)
        app.buttons["Delete Collection"].tap()
        XCTAssertTrue(app.alerts.staticTexts["Delete this collection? Items stay in the Box."].exists)
        app.alerts.buttons["Delete Collection"].tap()
        XCTAssertTrue(travel.waitForNonExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["box-item-demo-image"].exists)
    }

    func testNewCollectionFromChecklistAddsItemAndScopedMenuManagesIt() {
        app.buttons["box-item-demo-agent-text"].tap()
        app.buttons["Add to Collection…"].tap()
        app.buttons["New Collection…"].tap()
        let name = app.textFields["box-collection-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Checklist collection")
        app.buttons["Save"].tap()
        let membership = app.buttons.containing(.staticText, identifier: "Checklist collection").firstMatch
        XCTAssertTrue(membership.waitForExistence(timeout: 5))
        assertSelected(membership, true)
        XCTAssertTrue(membership.staticTexts["1"].exists)
        app.buttons["Done"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["box-collections"].tap()
        app.buttons.containing(.staticText, identifier: "Checklist collection").firstMatch.tap()
        XCTAssertTrue(app.buttons["box-item-demo-agent-text"].waitForExistence(timeout: 5))
        app.buttons["box-collection-menu"].tap()
        app.buttons["Rename"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20) + "Renamed")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Renamed"].waitForExistence(timeout: 5))
        app.buttons["box-collection-menu"].tap()
        app.buttons["Delete Collection"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["Delete Collection"].tap()
        XCTAssertTrue(app.navigationBars["Collections"].waitForExistence(timeout: 5))
    }

    func testLeadingSwipeAndContextMenuToggleLike() {
        let row = app.buttons["box-item-demo-agent-text"]
        row.press(forDuration: 1)
        app.buttons["Like"].tap()
        XCTAssertTrue(row.label.contains("Liked"))
        row.swipeRight()
        app.buttons["Unlike"].tap()
        XCTAssertFalse(row.label.contains("Liked"))
    }

    func testFailedLikeKeepsPreviousStateAndInlineError() {
        app.terminate()
        app.configureDemoLaunch(["HIBOSS_DEMO_BOX_LIKE_FAILURE": "1"])
        app.launchConfiguredDemo()
        app.tabBars.buttons["Box"].tap()
        let row = app.buttons["box-item-demo-agent-text"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        app.buttons["box-like"].tap()
        XCTAssertTrue(app.staticTexts["box-organization-error"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["box-like"].label, "Like")
    }

    func testEnglishLightCollectionScreens() { localizedCapture(dark: false, large: false, english: true) }

    func testChineseDarkCollectionScreens() { localizedCapture(dark: true, large: false) }
    func testChineseLargeCollectionScreens() { localizedCapture(dark: false, large: true) }

    private func localizedCapture(dark: Bool, large: Bool, english: Bool = false) {
        app.terminate()
        app.launchArguments = ["-AppleLanguages", english ? "(en)" : "(zh-Hans)",
                               "-AppleLocale", english ? "en_US" : "zh_CN",
                               "-AppleInterfaceStyle", dark ? "Dark" : "Light"]
        if large {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName",
                                    "UICTContentSizeCategoryAccessibilityL"]
        }
        let prefix = english ? "en-light" : dark ? "zh-dark" : "zh-large"
        app.launchConfiguredDemo()
        app.tabBars.buttons.element(boundBy: 2).tap()
        XCTAssertTrue(app.buttons["box-collections"].waitForExistence(timeout: 10))
        app.buttons["box-filter-liked"].tap()
        XCTAssertTrue(app.buttons["box-filter-liked"].isSelected)
        capture("\(prefix)-liked-list")
        app.buttons["box-collections"].tap()
        XCTAssertTrue(app.buttons["box-collection-demo-design"].waitForExistence(timeout: 5))
        capture("\(prefix)-collection-grid")
        app.buttons["box-collection-demo-design"].tap()
        XCTAssertTrue(app.buttons["box-collection-menu"].waitForExistence(timeout: 5))
        capture("\(prefix)-scoped-list")
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["box-item-demo-text"].tap()
        app.buttons[english ? "Add to Collection…" : "加入集合…"].tap()
        XCTAssertTrue(app.buttons["box-membership-demo-design"].waitForExistence(timeout: 5))
        assertSelected(app.buttons["box-membership-demo-design"], false)
        assertSelected(app.buttons["box-membership-demo-reading"], true)
        capture("\(prefix)-add-sheet")
    }

    private func assertSelected(_ element: XCUIElement, _ selected: Bool) {
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            element.isSelected == selected
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
