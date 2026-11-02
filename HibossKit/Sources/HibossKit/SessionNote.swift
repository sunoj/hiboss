// Session-specific boss notes, independent of message delivery and replies.
// Exports SessionNote and SessionNotesServing for native clients and demo services.
// Dependencies: Foundation and HibossAPI authenticated requests.

import Foundation

public struct SessionNote: Codable, Identifiable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case pending, read }
    public let id: String
    public let sessionID: String
    public let agentID: String
    public let bossName: String
    public let body: String
    public let status: Status
    public let createdAt: String
    public let readAt: String?

    enum CodingKeys: String, CodingKey {
        case id, body, status
        case sessionID = "session_id", agentID = "agent_id", bossName = "boss_name"
        case createdAt = "created_at", readAt = "read_at"
    }

    public init(id: String, sessionID: String, agentID: String, bossName: String,
                body: String, status: Status, createdAt: String, readAt: String? = nil) {
        self.id = id
        self.sessionID = sessionID
        self.agentID = agentID
        self.bossName = bossName
        self.body = body
        self.status = status
        self.createdAt = createdAt
        self.readAt = readAt
    }
}

public protocol SessionNotesServing: Sendable {
    func listSessionNotes(sessionID: String) async throws -> [SessionNote]
    func createSessionNote(
        sessionID: String, body: String, idempotencyKey: String
    ) async throws -> SessionNote
    func canCreateSessionNotes() async throws -> Bool
}

extension HibossAPI: SessionNotesServing {
    public func listSessionNotes(sessionID: String) async throws -> [SessionNote] {
        struct Response: Decodable { let notes: [SessionNote] }
        return try await decode(Response.self, from: notesURL(sessionID), context: "session notes").notes
    }

    public func createSessionNote(
        sessionID: String, body: String, idempotencyKey: String
    ) async throws -> SessionNote {
        struct Payload: Encodable { let body: String }
        var request = authorizedRequest(url: notesURL(sessionID), method: "POST")
        request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        request.httpBody = try JSONEncoder().encode(Payload(body: body))
        return try decoder.decode(SessionNote.self, from: await validatedData(for: request))
    }

    public func canCreateSessionNotes() async throws -> Bool {
        struct Identity: Decodable { let role: String }
        let identity = try await decode(
            Identity.self, from: apiURL.appendingPathComponent("me"), context: "account")
        return identity.role == "admin" || identity.role == "manager"
    }

    private func notesURL(_ sessionID: String) -> URL {
        apiURL.appendingPathComponent("sessions")
            .appendingPathComponent(sessionID).appendingPathComponent("notes")
    }
}
