// Wire contracts for immutable questionnaires and durable answer receipts.
// Exports request models and the injectable QuestionnaireServing API.
// Dependencies: Foundation and the shared panel spec/value types.

import Foundation

public struct QuestionnaireRecord: Codable, Equatable, Identifiable, Sendable {
    public let requestId: String
    public let panelId: String
    public let requestRevision: Int
    public let definitionRevision: Int
    public let state: String
    public let expiresAt: String?
    public let withdrawalReason: String?
    public let definition: QuestionnaireDefinition
    public let submission: QuestionnaireSubmission?
    public var id: String { requestId }
    public func isOpen(at now: Date) -> Bool {
        state == "open" && (panelDate(expiresAt).map { $0 > now } ?? true)
    }
}

public struct PendingQuestionnaire: Codable, Equatable, Identifiable, Sendable {
    public let requestId: String
    public let panelId: String
    public let requestRevision: Int
    public let title: String
    public let blocking: Bool
    public let expiresAt: String?
    public let createdAt: String
    public var id: String { requestId }
}

public struct QuestionnaireDefinition: Codable, Equatable, Sendable {
    public let title: String
    public let kind: String
    public let blocking: Bool
    public let formSpec: PanelSpec
    public let answerSchema: PanelValue
    public let defaults: PanelValue
    public let context: PanelValue
}

public struct QuestionnaireSubmission: Codable, Equatable, Sendable {
    public let submissionId: String
    public let requestId: String
    public let requestRevision: Int
    public let answers: PanelValue
    public let acceptedAt: String
    public let delivery: String
}

public struct QuestionnaireReceipt: Codable, Sendable {
    public let submissionId: String
    public let requestId: String
    public let requestRevision: Int
    public let acceptedAt: String
    public let delivery: String
}

public protocol QuestionnaireServing: Sendable {
    var questionnaireScope: String { get }
    func fetchPendingQuestionnaires() async throws -> [PendingQuestionnaire]
    func fetchQuestionnaires(panelID: String) async throws -> [QuestionnaireRecord]
    func fetchQuestionnaire(_ id: String) async throws -> QuestionnaireRecord
    func fetchQuestionnaireSubmission(requestID: String, submissionID: String) async throws -> QuestionnaireSubmission
    func submitQuestionnaire(_ request: QuestionnaireRecord, bossID: String, submissionID: String, answers: PanelValue) async throws -> QuestionnaireReceipt
}
