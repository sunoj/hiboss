// Sends questionnaire answers with a purpose-specific JWS for paired credentials.
// Exports HibossAPI's QuestionnaireServing conformance.
// Dependencies: URLSession, existing signature providers, and typed request models.

import Foundation

extension HibossAPI: QuestionnaireServing {
    public var questionnaireScope: String { config.serverURL.absoluteString }
    private var questionnairesURL: URL { config.serverURL.appendingPathComponent("api/interaction-requests") }

    public func fetchPendingQuestionnaires() async throws -> [PendingQuestionnaire] {
        var requests: [PendingQuestionnaire] = []
        var cursor: String?
        var visited: Set<String> = []
        repeat {
            try Task.checkCancellation()
            var url = questionnairesURL
            if let cursor { url.append(queryItems: [URLQueryItem(name: "cursor", value: cursor)]) }
            let page = try await decode(PendingQuestionnairePage.self, from: url, context: "pending questionnaires")
            requests.append(contentsOf: page.requests)
            cursor = page.nextCursor
            if let cursor, !visited.insert(cursor).inserted { throw HibossAPIError.invalidResponse }
        } while cursor != nil
        return requests
    }

    public func fetchQuestionnaires(panelID: String) async throws -> [QuestionnaireRecord] {
        let page = try await decode(QuestionnairePage.self, from: panelsURL.appendingPathComponent(panelID).appendingPathComponent("requests"), context: "questionnaires")
        return page.requests
    }

    public func fetchQuestionnaire(_ id: String) async throws -> QuestionnaireRecord {
        try await decode(QuestionnaireRecord.self, from: questionnairesURL.appendingPathComponent(id), context: "questionnaire")
    }

    public func fetchQuestionnaireSubmission(requestID: String, submissionID: String) async throws -> QuestionnaireSubmission {
        try await decode(QuestionnaireSubmission.self, from: questionnairesURL.appendingPathComponent(requestID).appendingPathComponent("submissions").appendingPathComponent(submissionID), context: "questionnaire receipt")
    }

    public func submitQuestionnaire(_ record: QuestionnaireRecord, bossID: String, submissionID: String, answers: PanelValue) async throws -> QuestionnaireReceipt {
        let payload = QuestionnairePayload(submissionId: submissionID, requestId: record.requestId, requestRevision: record.requestRevision, bossId: bossID, answers: answers)
        let signed = try messageSigner.map { try payload.sign(using: $0) }
        var request = authorizedRequest(url: questionnairesURL.appendingPathComponent(record.requestId).appendingPathComponent("submissions"), method: "POST")
        var object = try JSONDecoder().decode([String: PanelValue].self, from: JSONEncoder().encode(payload))
        if let signed { object["signedSubmission"] = .string(signed) }
        request.httpBody = try JSONEncoder().encode(object)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400,
           let error = try? JSONDecoder().decode(QuestionnaireError.self, from: data) {
            throw HibossAPIError.requestFailed(status: http.statusCode, message: error.error.message)
        }
        try validate(response)
        return try decoder.decode(QuestionnaireReceipt.self, from: data)
    }
}

private struct QuestionnairePage: Decodable { let requests: [QuestionnaireRecord] }
private struct PendingQuestionnairePage: Decodable { let requests: [PendingQuestionnaire]; let nextCursor: String? }
private struct QuestionnaireError: Decodable {
    struct Detail: Decodable { let message: String }
    let error: Detail
}

struct QuestionnairePayload: Encodable {
    let protocolVersion = 1
    let purpose = "hiboss.interaction-submit"
    let submissionId: String
    let requestId: String
    let requestRevision: Int
    let bossId: String
    let answers: PanelValue

    func sign(using provider: any BossMessageSignatureProvider) throws -> String {
        let encoder = JSONEncoder()
        let header = try encoder.encode(["alg": "ES256", "kid": provider.keyID, "typ": "hiboss-interaction+jws"])
        var object = try JSONDecoder().decode([String: PanelValue].self, from: encoder.encode(self))
        object["issuedAt"] = .number(Date().timeIntervalSince1970.rounded(.down))
        let input = "\(header.questionnaireBase64).\(try encoder.encode(object).questionnaireBase64)"
        return "\(input).\(try provider.signature(for: Data(input.utf8)).questionnaireBase64)"
    }
}

private extension Data {
    var questionnaireBase64: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
