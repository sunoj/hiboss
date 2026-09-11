// Verifies draft isolation, expiry, and durable submission recovery without UI execution.
// Exports model unit tests using an in-memory service and isolated UserDefaults.
// Dependencies: XCTest and HibossKit; no network, browser, or application launch.

import XCTest
@testable import HibossKit

@MainActor
final class QuestionnaireModelTests: XCTestCase {
    func testDraftRestoresOnlyWithinSameBossAndRevision() {
        let (model, service, storage) = fixture()
        model.store.setNumber(7, at: "/form/count")
        model.save()
        let restored = QuestionnaireModel(record: question(), bossID: "boss", service: service, storage: storage)
        XCTAssertEqual(restored.answers.object?["count"], .number(7))
        let other = QuestionnaireModel(record: question(), bossID: "other", service: service, storage: storage)
        XCTAssertEqual(other.answers.object?["count"], .number(3))
        model.update(question(revision: 2))
        XCTAssertFalse(model.canEdit)
        model.restart()
        XCTAssertEqual(model.answers.object?["count"], .number(3))
        XCTAssertEqual(restored.answers.object?["count"], .number(7))
    }

    func testExpiredQuestionCannotBeEditedOrSubmitted() async {
        let record = question(expiresAt: "2000-01-01T00:00:00Z")
        let (model, service, _) = fixture(record)
        XCTAssertFalse(model.canEdit)
        await model.submit()
        let count = await service.submissions
        XCTAssertEqual(count, 0)
    }

    func testStaleReadAfterAcceptancePreservesRecoveryUntilAnswerIsReadBack() async throws {
        let (model, service, storage) = fixture()
        await model.submit()
        let pending = try XCTUnwrap(model.pendingID)
        let restored = QuestionnaireModel(record: question(), bossID: "boss", service: service, storage: storage)
        XCTAssertEqual(restored.pendingID, pending)
        await service.showAccepted()
        await restored.recover()
        XCTAssertNil(restored.pendingID)
        XCTAssertEqual(restored.latest.submission?.answers.object?["count"], .number(3))
        let count = await service.submissions
        XCTAssertEqual(count, 1)
    }

    func testUnconfirmedSubmissionDoesNotResendAndKeepsDraft() async throws {
        let (model, service, storage) = fixture()
        await service.failAfterAccepting()
        model.store.setNumber(8, at: "/form/count")
        await model.submit()
        XCTAssertNotNil(model.pendingID)
        XCTAssertFalse(model.canEdit)
        await model.submit()
        await service.showAccepted()
        await model.recover()
        XCTAssertNil(model.pendingID)
        XCTAssertEqual(model.latest.submission?.answers.object?["count"], .number(8))
        let count = await service.submissions
        XCTAssertEqual(count, 1)
        let reopened = QuestionnaireModel(record: question(), bossID: "boss", service: service, storage: storage)
        XCTAssertEqual(reopened.answers.object?["count"], .number(3))
    }

    func testOlderPollCannotReopenAnAcceptedQuestion() async {
        let (model, service, _) = fixture()
        await model.submit()
        await service.showAccepted()
        await model.recover()
        model.update(question())
        XCTAssertEqual(model.latest.state, "accepted")
        XCTAssertFalse(model.canEdit)
    }

    func testPointerWritesRoundTripEscapedKeysAndRejectNonFiniteNumbers() throws {
        let (model, _, _) = fixture()
        model.store.setString("answer", at: "/form/a~1b~0c")
        XCTAssertEqual(model.answers.object?["a/b~c"], .string("answer"))
        model.store.setText("inf", at: "/form/count")
        XCTAssertEqual(model.answers.object?["count"], .string("inf"))
        XCTAssertNoThrow(try JSONEncoder().encode(model.answers))
        model.store.setNumber(.infinity, at: "/form/count")
        XCTAssertNoThrow(try JSONEncoder().encode(model.answers))
        model.store.setText("3.5", at: "/form/count")
        XCTAssertEqual(model.answers.object?["count"], .number(3.5))
    }

    func testNumericDisplayPreservesLargeAndSmallValues() {
        XCTAssertEqual(Double(PanelValue.number(1e100).displayText), 1e100)
        XCTAssertEqual(Double(PanelValue.number(1e-100).displayText), 1e-100)
        XCTAssertEqual(PanelValue.number(3).displayText, "3")
    }

    private func fixture(_ record: QuestionnaireRecord? = nil) -> (QuestionnaireModel, QuestionnaireStub, UserDefaults) {
        let record = record ?? question()
        let service = QuestionnaireStub(record)
        let suite = "QuestionnaireModelTests.\(UUID())"
        let storage = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        return (QuestionnaireModel(record: record, bossID: "boss", service: service, storage: storage), service, storage)
    }
}

private func question(revision: Int = 1, expiresAt: String? = nil) -> QuestionnaireRecord {
    let spec = PanelSpec(root: "count", elements: ["count": PanelElement(type: "NumberInput",
        props: ["label": .string("Count"), "value": .object(["$bindState": .string("/form/count")])], children: [], on: nil)])
    let definition = QuestionnaireDefinition(title: "Settings", kind: "intake", blocking: true, formSpec: spec,
        answerSchema: .object([:]), defaults: .object(["count": .number(3)]), context: .object([:]))
    return QuestionnaireRecord(requestId: "request", panelId: "panel", requestRevision: revision,
        definitionRevision: 1, state: "open", expiresAt: expiresAt, withdrawalReason: nil, definition: definition, submission: nil)
}

private actor QuestionnaireStub: QuestionnaireServing {
    nonisolated let questionnaireScope = "https://unit.test"
    var current: QuestionnaireRecord
    var accepted: QuestionnaireSubmission?
    var submissions = 0
    var shouldFail = false
    init(_ record: QuestionnaireRecord) { current = record }
    func fetchPendingQuestionnaires() async throws -> [PendingQuestionnaire] { [] }
    func fetchQuestionnaires(panelID: String) async throws -> [QuestionnaireRecord] { [current] }
    func fetchQuestionnaire(_ id: String) async throws -> QuestionnaireRecord { current }
    func fetchQuestionnaireSubmission(requestID: String, submissionID: String) async throws -> QuestionnaireSubmission {
        guard let accepted else { throw HibossAPIError.requestFailed(status: 404, message: "Missing") }
        return accepted
    }
    func submitQuestionnaire(_ request: QuestionnaireRecord, bossID: String, submissionID: String, answers: PanelValue) async throws -> QuestionnaireReceipt {
        submissions += 1
        accepted = QuestionnaireSubmission(submissionId: submissionID, requestId: request.requestId,
            requestRevision: request.requestRevision, answers: answers, acceptedAt: "2026-09-11T00:00:00Z", delivery: "pending")
        if shouldFail { throw URLError(.networkConnectionLost) }
        return QuestionnaireReceipt(submissionId: submissionID, requestId: request.requestId,
            requestRevision: request.requestRevision, acceptedAt: "2026-09-11T00:00:00Z", delivery: "pending")
    }
    func failAfterAccepting() { shouldFail = true }
    func showAccepted() {
        current = QuestionnaireRecord(requestId: current.requestId, panelId: current.panelId, requestRevision: current.requestRevision,
            definitionRevision: current.definitionRevision, state: "accepted", expiresAt: nil, withdrawalReason: nil,
            definition: current.definition, submission: accepted)
    }
}
