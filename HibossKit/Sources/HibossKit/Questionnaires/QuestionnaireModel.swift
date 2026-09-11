// Preserves revision-pinned drafts and reconciles ambiguous durable submissions.
// Exports QuestionnaireModel; network failures never trigger automatic resubmission.
// Dependencies: injectable questionnaire service, UserDefaults, and PanelStore.

import SwiftUI

@MainActor
public final class QuestionnaireModel: ObservableObject {
    @Published public private(set) var editing: QuestionnaireRecord
    @Published public private(set) var latest: QuestionnaireRecord
    @Published public private(set) var store: PanelStore
    @Published public private(set) var pendingID: String?
    @Published public private(set) var isSending = false
    @Published public private(set) var error: String?
    @Published public private(set) var hasSavedDraft = false
    @Published public private(set) var isRecovering = false
    private let currentTime: @MainActor () -> Date
    private let service: any QuestionnaireServing
    private let bossID: String
    private let storage: UserDefaults

    public init(record: QuestionnaireRecord, bossID: String, service: any QuestionnaireServing, storage: UserDefaults = .standard,
                currentTime: @escaping @MainActor () -> Date = { Date() }) {
        self.editing = record
        self.latest = record
        self.bossID = bossID
        self.service = service
        self.storage = storage
        self.currentTime = currentTime
        let key = Self.draftKey(record, bossID: bossID, scope: service.questionnaireScope)
        let saved = storage.data(forKey: key).flatMap { try? JSONDecoder().decode(Draft.self, from: $0) }
        pendingID = saved?.submissionID
        hasSavedDraft = saved != nil
        store = PanelStore(fixture: PanelFixture(questionnaire: record, answers: saved?.answers ?? record.definition.defaults))
        connectSubmission()
    }

    public var canEdit: Bool { latest.isOpen(at: currentTime()) && !hasNewRevision && pendingID == nil && !isSending }
    public var hasNewRevision: Bool { latest.requestRevision != editing.requestRevision }
    public var answers: PanelValue { panelValue(at: "/form", in: store.state) ?? .object([:]) }

    public func update(_ record: QuestionnaireRecord) {
        guard record.requestRevision >= latest.requestRevision else { return }
        if latest.state != "open", record.state == "open" { return }
        latest = record
    }

    public func save() {
        guard latest.submission == nil else { return }
        let draft = Draft(answers: answers, submissionID: pendingID)
        if let data = try? JSONEncoder().encode(draft) { storage.set(data, forKey: draftKey); hasSavedDraft = true }
    }

    public func restart() {
        guard pendingID == nil, !isSending else { return }
        save()
        editing = latest
        store = PanelStore(fixture: PanelFixture(questionnaire: latest, answers: latest.definition.defaults))
        error = nil
        connectSubmission()
        save()
    }

    public func submit() async {
        guard canEdit else { return }
        isSending = true
        error = nil
        defer { isSending = false }
        do {
            update(try await service.fetchQuestionnaire(editing.requestId))
            guard latest.isOpen(at: currentTime()), !hasNewRevision else { return }
            let id = UUID().uuidString.lowercased()
            pendingID = id
            save()
            _ = try await service.submitQuestionnaire(editing, bossID: bossID, submissionID: id, answers: answers)
            // Keep the recovery ID until the accepted answer itself has been read back.
            update(try await service.fetchQuestionnaire(editing.requestId))
            clearConfirmedDraft(id)
        } catch {
            if let failure = error as? HibossAPIError, case let .requestFailed(status, _) = failure, (400..<500).contains(status) {
                pendingID = nil
                if let current = try? await service.fetchQuestionnaire(editing.requestId) { update(current) }
            }
            self.error = error.localizedDescription
            save()
        }
    }

    public func recover() async {
        guard let pendingID, !isSending else { return }
        isSending = true
        isRecovering = true
        defer { isSending = false; isRecovering = false }
        do {
            _ = try await service.fetchQuestionnaireSubmission(requestID: editing.requestId, submissionID: pendingID)
            update(try await service.fetchQuestionnaire(editing.requestId))
            clearConfirmedDraft(pendingID)
            error = nil
        } catch let failure as HibossAPIError {
            if case .requestFailed(status: 404, _) = failure {
                do {
                    update(try await service.fetchQuestionnaire(editing.requestId))
                    self.pendingID = nil
                    error = kitL("No saved answer found. Review your answers before submitting again.")
                    save()
                } catch { self.error = error.localizedDescription }
            } else { error = failure.localizedDescription }
        } catch { self.error = error.localizedDescription }
    }

    private func clearConfirmedDraft(_ submissionID: String) {
        guard latest.submission?.submissionId == submissionID else { return }
        pendingID = nil
        storage.removeObject(forKey: draftKey)
        hasSavedDraft = false
    }

    private func connectSubmission() {
        store.onSubmit = { [weak self] _ in Task { await self?.submit() } }
    }
    private var draftKey: String { Self.draftKey(editing, bossID: bossID, scope: service.questionnaireScope) }
    private static func draftKey(_ record: QuestionnaireRecord, bossID: String, scope: String) -> String {
        "hiboss.questionnaire.\(scope).\(bossID).\(record.requestId).\(record.requestRevision)"
    }
    private struct Draft: Codable { let answers: PanelValue; let submissionID: String? }
}
