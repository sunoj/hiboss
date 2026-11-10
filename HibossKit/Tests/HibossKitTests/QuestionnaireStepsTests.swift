// Verifies client-side questionnaire step derivation, required-field gating and review rows.
// Exports QuestionnaireStepsTests; pure model tests with no UI execution.
// Dependencies: XCTest and the shared QuestionnaireSteps derivation.

import XCTest
@testable import HibossKit

final class QuestionnaireStepsTests: XCTestCase {
    func testTopLevelInputsBecomeStepsWithIntroAndOptionalNotes() throws {
        let questions = (1...10).map { "q\($0)" }
        var elements = Dictionary(uniqueKeysWithValues: questions.map { ($0, select($0)) })
        elements["form"] = stack(["intro"] + questions + ["notes"])
        elements["intro"] = text()
        elements["notes"] = input("TextArea", "notes")
        let steps = try XCTUnwrap(QuestionnaireSteps(spec: spec(elements), answerSchema: schema(questions)))
        XCTAssertEqual(steps.intro, ["intro"])
        XCTAssertEqual(steps.steps.count, 11)
        XCTAssertEqual(steps.steps[0].elementIDs, ["q1"])
        XCTAssertEqual(steps.steps[0].fields, [QuestionnaireField(path: "/form/q1", label: "Question q1", required: true, options: options)])
        XCTAssertEqual(steps.steps[10].fields.map(\.required), [false])
    }

    func testSectionKeepsInputsTogetherAndDisplayItemsAttachToTheFollowingStep() throws {
        let elements: [String: PanelElement] = [
            "form": stack(["lead", "group", "between", "q3", "q4", "tail", "submit"]),
            "lead": text(), "between": text(), "tail": text(),
            "group": PanelElement(type: "Section", props: ["label": .string("Pair")], children: ["q1", "q2"], on: nil),
            "q1": select("q1"), "q2": select("q2"), "q3": select("q3"), "q4": select("q4"),
            "submit": PanelElement(type: "Button", props: ["label": .string("Send")], children: [],
                                   on: ["press": PanelAction(action: "submitRequest", params: nil)]),
        ]
        let steps = try XCTUnwrap(QuestionnaireSteps(spec: spec(elements), answerSchema: schema(["q1", "q2", "q3"])))
        XCTAssertEqual(steps.intro, ["lead"])
        XCTAssertEqual(steps.steps.map(\.elementIDs), [["group"], ["between", "q3"], ["q4", "tail"]])
        XCTAssertEqual(steps.steps[0].fields.map(\.path), ["/form/q1", "/form/q2"])
        XCTAssertNil(steps.spec.elements["submit"], "the review page owns submission")
        XCTAssertFalse(steps.spec.elements["form"]?.children.contains("submit") ?? true)
    }

    func testShortOrFlatFormsKeepTheSinglePage() {
        let two: [String: PanelElement] = ["form": stack(["q1", "submitless", "q2"]), "q1": select("q1"),
                                           "submitless": text(), "q2": select("q2")]
        XCTAssertNil(QuestionnaireSteps(spec: spec(two), answerSchema: schema([])))
        XCTAssertNil(QuestionnaireSteps(spec: PanelSpec(root: "q1", elements: ["q1": select("q1")]), answerSchema: schema([])))
    }

    func testRequiredFieldsGateTheStepAndOptionalFieldsMaySkip() throws {
        let steps = try tenQuestionSteps()
        var state = formState([:])
        XCTAssertEqual(steps.missingRequired(inStep: 0, state: state).map(\.path), ["/form/q1"])
        state = formState(["q1": .string(""), "q2": .array([]), "q3": .null])
        XCTAssertFalse(steps.isComplete(inStep: 0, state: state))
        XCTAssertFalse(steps.isComplete(inStep: 1, state: state))
        XCTAssertFalse(steps.isComplete(inStep: 2, state: state))
        state = formState(["q1": .string("a"), "q2": .array([.string("b")]), "q3": .bool(false)])
        XCTAssertTrue(steps.isComplete(inStep: 0, state: state))
        XCTAssertTrue(steps.isComplete(inStep: 1, state: state))
        XCTAssertTrue(steps.isComplete(inStep: 2, state: state))
        XCTAssertTrue(steps.isComplete(inStep: 3, state: state), "an optional field may be skipped")
        XCTAssertTrue(steps.allRequiredAnswered(state: state))
    }

    func testInitialStepIsTheFirstUnansweredRequiredFieldOrTheReview() throws {
        let steps = try tenQuestionSteps()
        XCTAssertEqual(steps.initialIndex(state: formState([:])), 0)
        XCTAssertEqual(steps.initialIndex(state: formState(["q1": .string("a"), "q2": .string("b")])), 2)
        let all = Dictionary(uniqueKeysWithValues: (1...3).map { ("q\($0)", PanelValue.string("a")) })
        XCTAssertTrue(steps.allRequiredAnswered(state: formState(all)))
        XCTAssertEqual(steps.initialIndex(state: formState(all)), steps.steps.count)
    }

    func testReviewRowsUseOptionLabelsAndMarkSkippedFields() throws {
        let steps = try tenQuestionSteps()
        let rows = steps.reviewRows(state: formState(["q1": .string("b")]))
        XCTAssertEqual(rows.first, QuestionnaireReviewRow(id: "/form/q1", step: 0, label: "Question q1", value: "Beta", required: true))
        XCTAssertEqual(rows.last?.step, 3)
        XCTAssertNil(rows.last?.value)
    }

    private let options: [PanelValue] = [
        .object(["id": .string("a"), "label": .string("Alpha"), "description": .string("Fast")]),
        .object(["id": .string("b"), "label": .string("Beta")]),
    ]

    private func tenQuestionSteps() throws -> QuestionnaireSteps {
        let elements: [String: PanelElement] = [
            "form": stack(["q1", "q2", "q3", "notes"]), "q1": select("q1"),
            "q2": input("MultiSelect", "q2"), "q3": input("Toggle", "q3"), "notes": input("TextArea", "notes"),
        ]
        return try XCTUnwrap(QuestionnaireSteps(spec: spec(elements), answerSchema: schema(["q1", "q2", "q3"])))
    }

    private func formState(_ answers: [String: PanelValue]) -> PanelValue {
        .object(["form": .object(answers), "context": .object([:])])
    }

    private func spec(_ elements: [String: PanelElement]) -> PanelSpec { PanelSpec(root: "form", elements: elements) }
    private func stack(_ children: [String]) -> PanelElement {
        PanelElement(type: "Stack", props: ["direction": .string("vertical")], children: children, on: nil)
    }
    private func text() -> PanelElement { PanelElement(type: "Text", props: ["text": .string("Read me")], children: [], on: nil) }
    private func select(_ key: String) -> PanelElement {
        PanelElement(type: "Select", props: ["label": .string("Question \(key)"), "options": .array(options),
                                             "value": .object(["$bindState": .string("/form/\(key)")])], children: [], on: nil)
    }
    private func input(_ type: String, _ key: String) -> PanelElement {
        PanelElement(type: type, props: ["label": .string("Question \(key)"), "options": .array(options),
                                         "value": .object(["$bindState": .string("/form/\(key)")])], children: [], on: nil)
    }
    private func schema(_ required: [String]) -> PanelValue {
        .object(["type": .string("object"), "required": .array(required.map(PanelValue.string))])
    }
}
