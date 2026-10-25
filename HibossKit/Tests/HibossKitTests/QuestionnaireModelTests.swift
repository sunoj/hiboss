// Verifies draft isolation, expiry, answer access, and durable submission recovery without UI.
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
        let restored = QuestionnaireModel(record: question(), bossID: "boss", answerer: owner, service: service, storage: storage)
        XCTAssertEqual(restored.answers.object?["count"], .number(7))
        let other = QuestionnaireModel(record: question(), bossID: "other", answerer: BossIdentity(id: "other", role: "admin"), service: service, storage: storage)
        XCTAssertEqual(other.answers.object?["count"], .number(3))
        model.update(question(revision: 2))
        XCTAssertFalse(model.canEdit)
        model.restart()
        XCTAssertEqual(model.answers.object?["count"], .number(3))
        XCTAssertEqual(restored.answers.object?["count"], .number(7))
    }

    func testAuthorizationRejectionClearsQuestionnaireDraftAndDisablesEditing() {
        let (model, service, storage) = fixture()
        model.store.setNumber(7, at: "/form/count")
        model.save()
        XCTAssertTrue(model.hasSavedDraft)
        AccountAuthorization.shared.reject(HibossAPIError.requestFailed(status: 401, message: ""))
        XCTAssertFalse(model.canEdit)
        XCTAssertFalse(model.hasSavedDraft)
        XCTAssertEqual(model.answers, .object([:]))
        let restored = QuestionnaireModel(record: question(), bossID: "boss", answerer: owner,
                                          service: service, storage: storage)
        XCTAssertEqual(restored.answers.object?["count"], .number(3))
        AccountAuthorization.shared.connect(nil)
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
        let restored = QuestionnaireModel(record: question(), bossID: "boss", answerer: owner, service: service, storage: storage)
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
        let reopened = QuestionnaireModel(record: question(), bossID: "boss", answerer: owner, service: service, storage: storage)
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

    func testForbiddenSubmissionShowsAPermissionMessageAndKeepsTheAccount() async {
        defer { AccountAuthorization.shared.connect(nil) }
        let (model, service, _) = fixture()
        await service.deny()
        await model.submit()
        XCTAssertEqual(model.error, kitL("You don't have permission to do that."))
        XCTAssertFalse(AccountAuthorization.shared.hasRejectedAccount)
        XCTAssertNil(model.pendingID)
        XCTAssertTrue(model.canEdit, "A permission error must not lock the account out of its questionnaires")
    }

    func testAccessFollowsTheServerAnsweringRule() {
        XCTAssertEqual(QuestionnaireAccess(boss: owner, targetBossID: "boss"), .answerable)
        XCTAssertEqual(QuestionnaireAccess(boss: BossIdentity(id: "boss", role: "manager"), targetBossID: "boss"),
                       .answerable)
        XCTAssertEqual(QuestionnaireAccess(boss: BossIdentity(id: "boss", role: "viewer"), targetBossID: "boss"),
                       .roleCannotAnswer)
        XCTAssertEqual(QuestionnaireAccess(boss: BossIdentity(id: "admin", role: "admin"), targetBossID: "boss"),
                       .otherBoss)
        XCTAssertNil(QuestionnaireAccess.answerable.readOnlyReason)
    }

    func testOtherBossAndViewerSeeTheQuestionnaireReadOnly() async {
        let (owned, _, _) = fixture()
        XCTAssertTrue(owned.canEdit)
        for answerer in [BossIdentity(id: "admin", role: "admin"), BossIdentity(id: "boss", role: "viewer")] {
            let service = QuestionnaireStub(question())
            let model = QuestionnaireModel(record: question(), bossID: "boss", answerer: answerer, service: service,
                                           storage: UserDefaults(suiteName: "QuestionnaireAccess.\(UUID())")!)
            XCTAssertFalse(model.canEdit, answerer.id)
            XCTAssertNotNil(model.access.readOnlyReason)
            await model.submit()
            let count = await service.submissions
            XCTAssertEqual(count, 0, "A read-only viewer never sends answers")
        }
    }

    func testReadOnlyFormOmitsItsSubmitControls() {
        let record = question(submitControl: true)
        let storage = UserDefaults(suiteName: "QuestionnaireSubmitControl.\(UUID())")!
        let service = QuestionnaireStub(record)
        let owned = QuestionnaireModel(record: record, bossID: "boss", answerer: owner, service: service, storage: storage)
        XCTAssertNotNil(owned.formSpec.elements["submit"])
        XCTAssertEqual(owned.formSpec.elements["root"]?.children, ["count", "submit"])
        let other = QuestionnaireModel(record: record, bossID: "boss", answerer: BossIdentity(id: "admin", role: "admin"),
                                       service: service, storage: storage)
        XCTAssertNil(other.formSpec.elements["submit"], "A viewer who cannot answer sees no submit control")
        XCTAssertEqual(other.formSpec.elements["root"]?.children, ["count"])
        XCTAssertNotNil(other.formSpec.elements["count"])
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
        return (QuestionnaireModel(record: record, bossID: "boss", answerer: owner, service: service, storage: storage), service, storage)
    }
}

private let owner = BossIdentity(id: "boss", role: "admin")

private func question(revision: Int = 1, expiresAt: String? = nil, submitControl: Bool = false) -> QuestionnaireRecord {
    var elements = ["count": PanelElement(type: "NumberInput",
        props: ["label": .string("Count"), "value": .object(["$bindState": .string("/form/count")])], children: [], on: nil)]
    if submitControl {
        elements["submit"] = PanelElement(type: "Button", props: ["label": .string("Send")], children: [],
            on: ["press": PanelAction(action: "submitRequest", params: nil)])
        elements["root"] = PanelElement(type: "Stack", props: [:], children: ["count", "submit"], on: nil)
    }
    let spec = PanelSpec(root: submitControl ? "root" : "count", elements: elements)
    let definition = QuestionnaireDefinition(title: "Settings", kind: "intake", blocking: true, formSpec: spec,
        answerSchema: .object([:]), defaults: .object(["count": .number(3)]), context: .object([:]))
    return QuestionnaireRecord(requestId: "request", panelId: "panel", requestRevision: revision,
        definitionRevision: 1, state: "open", expiresAt: expiresAt, withdrawalReason: nil, definition: definition, submission: nil)
}

private actor QuestionnaireStub: QuestionnaireServing {
    nonisolated let questionnaireScope = "https://unit.test"
    func fetchBossIdentity() async throws -> BossIdentity { BossIdentity(id: "boss", role: "admin") }
    var current: QuestionnaireRecord
    var accepted: QuestionnaireSubmission?
    var submissions = 0
    var shouldFail = false
    var denied = false
    init(_ record: QuestionnaireRecord) { current = record }
    func fetchPendingQuestionnaires() async throws -> [PendingQuestionnaire] { [] }
    func fetchQuestionnaires(panelID: String) async throws -> [QuestionnaireRecord] { [current] }
    func fetchQuestionnaire(_ id: String) async throws -> QuestionnaireRecord { current }
    func fetchQuestionnaireSubmission(requestID: String, submissionID: String) async throws -> QuestionnaireSubmission {
        guard let accepted else { throw HibossAPIError.requestFailed(status: 404, message: "Missing") }
        return accepted
    }
    func submitQuestionnaire(_ request: QuestionnaireRecord, bossID: String, submissionID: String, answers: PanelValue) async throws -> QuestionnaireReceipt {
        if denied { throw HibossAPIError.requestFailed(status: 403, message: "permission_denied") }
        submissions += 1
        accepted = QuestionnaireSubmission(submissionId: submissionID, requestId: request.requestId,
            requestRevision: request.requestRevision, answers: answers, acceptedAt: "2026-09-11T00:00:00Z", delivery: "pending")
        if shouldFail { throw URLError(.networkConnectionLost) }
        return QuestionnaireReceipt(submissionId: submissionID, requestId: request.requestId,
            requestRevision: request.requestRevision, acceptedAt: "2026-09-11T00:00:00Z", delivery: "pending")
    }
    func failAfterAccepting() { shouldFail = true }
    func deny() { denied = true }
    func showAccepted() {
        current = QuestionnaireRecord(requestId: current.requestId, panelId: current.panelId, requestRevision: current.requestRevision,
            definitionRevision: current.definitionRevision, state: "accepted", expiresAt: nil, withdrawalReason: nil,
            definition: current.definition, submission: accepted)
    }
}
