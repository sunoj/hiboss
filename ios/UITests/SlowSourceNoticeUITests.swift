// Slow refresh notices retain the outstanding source on native cached surfaces.
// Exports SlowSourceNoticeUITests for compact device requests and shared questionnaire rows.
// Dependencies: controlled demo refresh latency and IntermediateCaptureCase.

import XCTest

final class SlowSourceNoticeUITests: IntermediateCaptureCase {
    override var variant: String { "en" }

    func testCompactSlowNoticeNamesDeviceRequests() {
        launch(["HIBOSS_DEMO_REQUESTS_EMPTY": "1", "HIBOSS_DEMO_REFRESH_DELAY_MS": "60000"])
        app.buttons["today-settings"].tap()
        app.buttons["settings-devices"].tap()
        app.buttons["Device Requests"].firstMatch.tap()
        let empty = app.descendants(matching: .any)["device-requests-empty"].firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 10))
        pause(6)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["Device requests are taking longer than expected."].firstMatch
            .waitForExistence(timeout: 12))
        capture("device-requests-slow-source")
    }

    func testSharedSlowNoticeNamesQuestionnaires() {
        launch(["HIBOSS_DEMO_NATIVE_PANEL": "1", "HIBOSS_DEMO_PANEL_OPEN": "demo-panel",
                "HIBOSS_DEMO_REFRESH_DELAY_MS": "60000"])
        XCTAssertTrue(app.navigationBars["Release checklist"].waitForExistence(timeout: 10))
        let submit = app.buttons["Submit checklist"].firstMatch
        reveal(submit)
        XCTAssertTrue(app.staticTexts["Questionnaires are taking longer than expected."].firstMatch
            .waitForExistence(timeout: 22))
        capture("questionnaires-slow-source")
    }
}
