// Verifies that step gating follows the answer schema: key presence plus the field's own constraints.
// Exports QuestionnaireSchemaGatingTests; covers empty values, nested bindings and Select clearing.
// Dependencies: XCTest, QuestionnaireSteps and PanelStore.

import XCTest
@testable import HibossKit

final class QuestionnaireSchemaGatingTests: XCTestCase {
    func testEmptyArrayAnswersARequiredFieldUnlessMinItemsRejectsIt() throws {
        let plain = try steps(["/form/a", "/form/b", "/form/c"], schema: """
            {"type":"object","required":["a"],"properties":{"a":{"type":"array"}}}
            """)
        XCTAssertTrue(plain.isComplete(inStep: 0, state: form(["a": []])), "[] is present and valid without minItems")
        XCTAssertFalse(plain.isComplete(inStep: 0, state: form([:])), "an absent key is unanswered")
        let bounded = try steps(["/form/a", "/form/b", "/form/c"], schema: """
            {"type":"object","required":["a"],"properties":{"a":{"type":"array","minItems":1}}}
            """)
        XCTAssertFalse(bounded.isComplete(inStep: 0, state: form(["a": []])))
        XCTAssertTrue(bounded.isComplete(inStep: 0, state: form(["a": ["x"]])))
    }

    func testEmptyStringAnswersARequiredFieldUnlessMinLengthRejectsIt() throws {
        let plain = try steps(["/form/a", "/form/b", "/form/c"], schema: """
            {"type":"object","required":["a"],"properties":{"a":{"type":"string"}}}
            """)
        XCTAssertTrue(plain.isComplete(inStep: 0, state: form(["a": ""])), "\"\" is present and valid without minLength")
        let bounded = try steps(["/form/a", "/form/b", "/form/c"], schema: """
            {"type":"object","required":["a"],"properties":{"a":{"type":"string","minLength":1,"maxLength":3}}}
            """)
        XCTAssertFalse(bounded.isComplete(inStep: 0, state: form(["a": ""])))
        XCTAssertTrue(bounded.isComplete(inStep: 0, state: form(["a": "abc"])))
        XCTAssertFalse(bounded.isComplete(inStep: 0, state: form(["a": "abcd"])), "maxLength applies too")
    }

    func testTypeEnumAndNumericBoundsGateRequiredAnswers() throws {
        let steps = try steps(["/form/a", "/form/b", "/form/c"], schema: """
            {"type":"object","required":["a","b"],"properties":{
              "a":{"type":"string","enum":["x","y"]},"b":{"type":"integer","minimum":1,"maximum":5}}}
            """)
        XCTAssertFalse(steps.isComplete(inStep: 0, state: form(["a": "z"])))
        XCTAssertTrue(steps.isComplete(inStep: 0, state: form(["a": "y"])))
        XCTAssertFalse(steps.isComplete(inStep: 1, state: form(["b": "3"])), "a string is not an integer")
        XCTAssertFalse(steps.isComplete(inStep: 1, state: form(["b": 2.5])))
        XCTAssertFalse(steps.isComplete(inStep: 1, state: form(["b": 6])))
        XCTAssertTrue(steps.isComplete(inStep: 1, state: form(["b": 5])))
    }

    func testNestedChildrenFollowTheirParentObjectsRequiredList() throws {
        let steps = try steps(["/form/profile/name", "/form/profile/notes", "/form/c"], schema: """
            {"type":"object","required":["profile"],"properties":{"profile":{"type":"object",
              "required":["name"],"properties":{"name":{"type":"string","minLength":1},"notes":{"type":"string"}}}}}
            """)
        let state = form(["profile": ["name": "Ada"]])
        XCTAssertTrue(steps.isComplete(inStep: 0, state: state))
        XCTAssertTrue(steps.isComplete(inStep: 1, state: state), "an optional child of a required parent may stay blank")
        XCTAssertEqual(steps.missingRequired(inStep: 0, state: form([:])).map(\.path), ["/form/profile/name"],
                       "a required child under a required parent is required even before the parent exists")
        XCTAssertTrue(steps.allRequiredAnswered(state: state))
    }

    func testRequiredChildOfAnOptionalParentAppliesOnlyWhenTheParentIsPresent() throws {
        let steps = try steps(["/form/a", "/form/extra/detail", "/form/c"], schema: """
            {"type":"object","required":["a"],"properties":{"a":{"type":"string"},
              "extra":{"$ref":"#/$defs/extra"}},
             "$defs":{"extra":{"type":"object","required":["detail"],"properties":{"detail":{"type":"string","minLength":2}}}}}
            """)
        XCTAssertTrue(steps.isComplete(inStep: 1, state: form(["a": "x"])), "an absent optional parent drops its children's requirements")
        XCTAssertFalse(steps.isComplete(inStep: 1, state: form(["a": "x", "extra": [:]])))
        XCTAssertFalse(steps.isComplete(inStep: 1, state: form(["a": "x", "extra": ["detail": "d"]])))
        XCTAssertTrue(steps.isComplete(inStep: 1, state: form(["a": "x", "extra": ["detail": "dd"]])))
    }

    @MainActor
    func testRemovingASelectAnswerDeletesTheKey() throws {
        let fixture = try PanelFixture(name: "select-clear", data: Data("""
            {"formSpec":{"root":"q","elements":{"q":{"type":"Text","props":{},"children":[]}}},"defaults":{"other":"kept"}}
            """.utf8))
        let store = PanelStore(fixture: fixture)
        store.setString("b", at: "/form/choice")
        XCTAssertEqual(panelValue(at: "/form/choice", in: store.state), .string("b"))
        store.removeValue(at: "/form/choice")
        XCTAssertNil(panelValue(at: "/form/choice", in: store.state), "clearing is the same as never answered")
        XCTAssertEqual(panelValue(at: "/form", in: store.state), .object(["other": .string("kept")]), "siblings stay")
        let before = store.state
        store.removeValue(at: "/form/missing/child")
        XCTAssertEqual(store.state, before, "removing an absent path changes nothing")
    }

    private func steps(_ paths: [String], schema: String) throws -> QuestionnaireSteps {
        var elements: [String: PanelElement] = [:]
        for (index, path) in paths.enumerated() {
            elements["q\(index)"] = PanelElement(type: "TextInput", props: [
                "label": .string(path), "value": .object(["$bindState": .string(path)])], children: [], on: nil)
        }
        elements["form"] = PanelElement(type: "Stack", props: [:], children: paths.indices.map { "q\($0)" }, on: nil)
        let decoded = try JSONDecoder().decode(PanelValue.self, from: Data(schema.utf8))
        return try XCTUnwrap(QuestionnaireSteps(spec: PanelSpec(root: "form", elements: elements), answerSchema: decoded))
    }

    private func form(_ answers: [String: Any]) -> PanelValue {
        .object(["form": json(answers), "context": .object([:])])
    }

    private func json(_ value: Any) -> PanelValue {
        switch value {
        case let text as String: return .string(text)
        case let number as Int: return .number(Double(number))
        case let number as Double: return .number(number)
        case let values as [Any]: return .array(values.map(json))
        case let object as [String: Any]: return .object(object.mapValues(json))
        default: return .null
        }
    }
}
