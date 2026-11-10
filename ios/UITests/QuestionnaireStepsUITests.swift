// Walks the ten-question demo intake one step at a time, through review, to submission.
// Exports QuestionnaireStepsUITests; QUESTIONNAIRE_APPEARANCE=Dark captures the dark variant.
// Dependencies: IntermediateCaptureCase, DemoStepQuestionnaire and the HibossKit stepper.

import XCTest

final class QuestionnaireStepsUITests: IntermediateCaptureCase {
    override var appearance: String? { ProcessInfo.processInfo.environment["QUESTIONNAIRE_APPEARANCE"] }

    func testStepThroughReviewAndSubmit() {
        launch(["HIBOSS_DEMO_NATIVE_PANEL": "1", "HIBOSS_DEMO_PANEL_OPEN": "demo-panel",
                "HIBOSS_DEMO_QUESTIONNAIRE_STEPS": "1"])
        XCTAssertTrue(app.navigationBars["Release checklist"].waitForExistence(timeout: 10))
        let counter = app.staticTexts["questionnaire-step-counter"]
        XCTAssertTrue(counter.waitForExistence(timeout: 10))
        XCTAssertEqual(counter.label, "Question 1 of 11")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '下面十个问题'")).firstMatch.exists,
                      "the intro shows on step 1")
        let next = app.buttons["questionnaire-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 3))
        XCTAssertFalse(next.isEnabled, "a required question gates Next")
        capture("questionnaire-step-1")

        let choice = option(1, "2")
        show(choice)
        choice.tap()
        XCTAssertTrue(choice.isSelected)
        choice.tap()
        XCTAssertTrue(choice.isSelected, "tapping the selected choice keeps it selected")
        show(next)
        XCTAssertTrue(next.isEnabled)
        next.tap()
        XCTAssertEqual(counter.label, "Question 2 of 11")
        app.buttons["questionnaire-back"].tap()
        XCTAssertEqual(counter.label, "Question 1 of 11")
        XCTAssertTrue(option(1, "2").isSelected, "Back keeps the earlier choice")
        show(next)
        next.tap()

        for question in 2...10 {
            XCTAssertEqual(counter.label, "Question \(question) of 11")
            let decide = option(question, "decide")
            show(decide)
            decide.tap()
            if question == 5 { capture("questionnaire-step-middle") }
            show(next)
            next.tap()
        }
        XCTAssertEqual(counter.label, "Question 11 of 11")
        show(next)
        XCTAssertTrue(next.isEnabled, "the optional notes step may be skipped")
        next.tap()
        XCTAssertEqual(counter.label, "Review your answers")
        let submit = app.buttons["Submit answers"].firstMatch
        show(submit)
        XCTAssertTrue(submit.isEnabled)
        capture("questionnaire-review")

        let firstRow = app.buttons["questionnaire-review-0"]
        show(firstRow, upward: false)
        firstRow.tap()
        XCTAssertEqual(counter.label, "Question 1 of 11", "a review row jumps back to its step")
        for _ in 0..<11 { show(next); next.tap() }
        XCTAssertEqual(counter.label, "Review your answers")
        show(submit)
        submit.tap()
        XCTAssertTrue(app.staticTexts["Answer saved"].waitForExistence(timeout: 10))
        capture("questionnaire-submitted")
    }

    /// Swipes, unlike a press-and-drag, never lands as a tap on a choice or review row.
    private func show(_ element: XCUIElement, upward: Bool = true) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        for _ in 0..<10 where !element.isHittable { upward ? app.swipeUp() : app.swipeDown() }
        XCTAssertTrue(element.isHittable)
    }

    private func option(_ question: Int, _ suffix: String) -> XCUIElement {
        app.buttons["panel-option-/form/q\(question)-q\(question)-\(suffix)"]
    }
}
