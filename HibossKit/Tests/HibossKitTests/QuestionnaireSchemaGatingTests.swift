// Verifies that step gating checks only presence of required keys; the server validates values.
// Exports QuestionnaireSchemaGatingTests; covers empty values, nested and nullable parents, Select clearing.
// Dependencies: XCTest, QuestionnaireSteps, QuestionnaireModel and PanelStore.

import XCTest
@testable import HibossKit

final class QuestionnaireSchemaGatingTests: XCTestCase {
    private let flat = """
        {"type":"object","required":["a"],"properties":{"a":{"type":"array","minItems":1}}}
        """

    func testAnyPresentValueAnswersARequiredField() throws {
        let steps = try steps(["/form/a", "/form/b", "/form/c"], schema: flat)
        XCTAssertFalse(steps.isComplete(inStep: 0, state: form([:])), "an absent key is unanswered")
        for value: Any in [[Any](), "", false, 0, NSNull()] {
            XCTAssertTrue(steps.isComplete(inStep: 0, state: form(["a": value])), "\(value) is present")
        }
    }

    func testAPresentValueViolatingMinLengthStillCountsAsAnswered() throws {
        let steps = try steps(["/form/a", "/form/b", "/form/c"], schema: """
            {"type":"object","required":["a"],"properties":{"a":{"type":"string","minLength":5}}}
            """)
        XCTAssertTrue(steps.isComplete(inStep: 0, state: form(["a": "ab"])), "the server decides on minLength")
    }

    func testNestedChildrenFollowTheirParentObjectsRequiredList() throws {
        let steps = try steps(["/form/profile/name", "/form/profile/notes", "/form/c"], schema: """
            {"type":"object","required":["profile"],"properties":{"profile":{"type":"object",
              "required":["name"],"properties":{"name":{"type":"string"},"notes":{"type":"string"}}}}}
            """)
        let state = form(["profile": ["name": "Ada"]])
        XCTAssertTrue(steps.isComplete(inStep: 0, state: state))
        XCTAssertTrue(steps.isComplete(inStep: 1, state: state), "an optional child of a required parent may stay blank")
        XCTAssertFalse(steps.isComplete(inStep: 0, state: form(["profile": [String: Any]()])),
                       "a present object parent makes its required child required")
        XCTAssertEqual(steps.missingRequired(inStep: 0, state: form([:])).map(\.path), ["/form/profile/name"],
                       "an absent required parent keeps its required child required")
        XCTAssertTrue(steps.allRequiredAnswered(state: state))
    }

    func testANullParentDropsItsChildrensRequirements() throws {
        let steps = try steps(["/form/profile/name", "/form/b", "/form/c"], schema: """
            {"type":"object","required":["profile"],"properties":{"profile":{"type":["object","null"],
              "required":["name"],"properties":{"name":{"type":"string"}}}}}
            """)
        XCTAssertTrue(steps.isComplete(inStep: 0, state: form(["profile": NSNull()])), "profile: null must not block")
    }

    func testRequiredChildOfAnOptionalParentAppliesOnlyWhenTheParentIsPresent() throws {
        let steps = try steps(["/form/a", "/form/extra/detail", "/form/c"], schema: """
            {"type":"object","required":["a"],"properties":{"a":{"type":"string"},
              "extra":{"$ref":"#/$defs/extra"}},
             "$defs":{"extra":{"type":"object","required":["detail"],"properties":{"detail":{"type":"string"}}}}}
            """)
        XCTAssertTrue(steps.isComplete(inStep: 1, state: form(["a": "x"])), "an absent optional parent drops its children's requirements")
        XCTAssertFalse(steps.isComplete(inStep: 1, state: form(["a": "x", "extra": [String: Any]()])))
        XCTAssertTrue(steps.isComplete(inStep: 1, state: form(["a": "x", "extra": ["detail": "d"]])))
    }

    @MainActor
    func testRemovingASelectAnswerDeletesTheKey() throws {
        let store = PanelStore(fixture: try fixture(defaults: #"{"other":"kept"}"#))
        store.setString("b", at: "/form/choice")
        XCTAssertEqual(panelValue(at: "/form/choice", in: store.state), .string("b"))
        store.removeValue(at: "/form/choice")
        XCTAssertNil(panelValue(at: "/form/choice", in: store.state), "clearing is the same as never answered")
        XCTAssertEqual(panelValue(at: "/form", in: store.state), .object(["other": .string("kept")]), "siblings stay")
        let before = store.state
        store.removeValue(at: "/form/missing/child")
        XCTAssertEqual(store.state, before, "removing an absent path changes nothing")
    }

    @MainActor
    func testRemovingThroughAnArrayIndexKeepsTheRowAndSiblings() throws {
        let store = PanelStore(fixture: try fixture(defaults: #"{"rows":[{"choice":"a","note":"n"},{"choice":"b"}]}"#))
        store.removeValue(at: "/form/rows/0/choice")
        XCTAssertEqual(panelValue(at: "/form/rows", in: store.state), .array([
            .object(["note": .string("n")]), .object(["choice": .string("b")])]))
        let before = store.state
        store.removeValue(at: "/form/rows/5/choice")
        XCTAssertEqual(store.state, before, "an out-of-range index changes nothing")
    }

    @MainActor
    func testAClearedAnswerStaysAbsentAcrossADraftRestore() throws {
        let suite = "QuestionnaireSchemaGatingTests.\(UUID())"
        let storage = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let record = try decode(QuestionnaireRecord.self, """
            {"requestId":"r","panelId":"p","requestRevision":1,"definitionRevision":1,"state":"open",
             "definition":{"title":"T","kind":"intake","blocking":true,"answerSchema":{},"context":{},
               "defaults":{"choice":"a","other":"kept"},
               "formSpec":{"root":"q","elements":{"q":{"type":"Text","props":{},"children":[]}}}}}
            """)
        let service = DraftOnlyService()
        let model = QuestionnaireModel(record: record, bossID: "boss", answerer: BossIdentity(id: "boss", role: "admin"),
                                       service: service, storage: storage)
        model.store.removeValue(at: "/form/choice")
        model.save()
        let restored = QuestionnaireModel(record: record, bossID: "boss", answerer: BossIdentity(id: "boss", role: "admin"),
                                          service: service, storage: storage)
        XCTAssertEqual(restored.answers, .object(["other": .string("kept")]), "the default does not come back")
    }

    private func fixture(defaults: String) throws -> PanelFixture {
        try PanelFixture(name: "select-clear", data: Data("""
            {"formSpec":{"root":"q","elements":{"q":{"type":"Text","props":{},"children":[]}}},"defaults":\(defaults)}
            """.utf8))
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private func steps(_ paths: [String], schema: String) throws -> QuestionnaireSteps {
        var elements: [String: PanelElement] = [:]
        for (index, path) in paths.enumerated() {
            elements["q\(index)"] = PanelElement(type: "TextInput", props: [
                "label": .string(path), "value": .object(["$bindState": .string(path)])], children: [], on: nil)
        }
        elements["form"] = PanelElement(type: "Stack", props: [:], children: paths.indices.map { "q\($0)" }, on: nil)
        let decoded = try decode(PanelValue.self, schema)
        return try XCTUnwrap(QuestionnaireSteps(spec: PanelSpec(root: "form", elements: elements), answerSchema: decoded))
    }

    private func form(_ answers: [String: Any]) -> PanelValue {
        .object(["form": json(answers), "context": .object([:])])
    }

    private func json(_ value: Any) -> PanelValue {
        switch value {
        case let flag as Bool: return .bool(flag)
        case let text as String: return .string(text)
        case let number as Int: return .number(Double(number))
        case let number as Double: return .number(number)
        case let values as [Any]: return .array(values.map(json))
        case let object as [String: Any]: return .object(object.mapValues(json))
        default: return .null
        }
    }
}

/// Only the draft key is read; the gating tests never submit.
private struct DraftOnlyService: QuestionnaireServing {
    let questionnaireScope = "https://unit.test"
    func fetchBossIdentity() async throws -> BossIdentity { BossIdentity(id: "boss", role: "admin") }
    func fetchPendingQuestionnaires() async throws -> [PendingQuestionnaire] { [] }
    func fetchQuestionnaires(panelID: String) async throws -> [QuestionnaireRecord] { [] }
    func fetchQuestionnaire(_ id: String) async throws -> QuestionnaireRecord { throw URLError(.unsupportedURL) }
    func fetchQuestionnaireSubmission(requestID: String, submissionID: String) async throws -> QuestionnaireSubmission {
        throw URLError(.unsupportedURL)
    }
    func submitQuestionnaire(_ request: QuestionnaireRecord, bossID: String, submissionID: String,
                             answers: PanelValue) async throws -> QuestionnaireReceipt { throw URLError(.unsupportedURL) }
}
