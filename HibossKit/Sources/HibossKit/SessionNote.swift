// Session-specific boss notes, with linked agent message replies.
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
    public let replies: [SessionNoteReply]
    public let images: [SessionNoteImage]

    enum CodingKeys: String, CodingKey {
        case id, body, status, images, replies
        case sessionID = "session_id", agentID = "agent_id", bossName = "boss_name"
        case createdAt = "created_at", readAt = "read_at"
    }

    public init(id: String, sessionID: String, agentID: String, bossName: String,
                body: String, status: Status, createdAt: String, readAt: String? = nil,
                images: [SessionNoteImage] = [], replies: [SessionNoteReply] = []) {
        self.id = id
        self.sessionID = sessionID
        self.agentID = agentID
        self.bossName = bossName
        self.body = body
        self.status = status
        self.createdAt = createdAt
        self.readAt = readAt
        self.images = images
        self.replies = replies
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        sessionID = try values.decode(String.self, forKey: .sessionID)
        agentID = try values.decode(String.self, forKey: .agentID)
        bossName = try values.decode(String.self, forKey: .bossName)
        body = try values.decode(String.self, forKey: .body)
        status = try values.decode(Status.self, forKey: .status)
        createdAt = try values.decode(String.self, forKey: .createdAt)
        readAt = try values.decodeIfPresent(String.self, forKey: .readAt)
        replies = try values.decodeIfPresent([SessionNoteReply].self, forKey: .replies) ?? []
        images = try values.decodeIfPresent([SessionNoteImage].self, forKey: .images) ?? []
    }
}

public protocol SessionNotesServing: Sendable {
    func listSessionNotes(sessionID: String) async throws -> [SessionNote]
    func createSessionNote(
        sessionID: String, body: String, images: [SessionNoteUpload], idempotencyKey: String
    ) async throws -> SessionNote
    func sessionNoteImage(sessionID: String, noteID: String, index: Int) async throws -> Data
    func canCreateSessionNotes() async throws -> Bool
}

extension HibossAPI: SessionNotesServing {
    public func listSessionNotes(sessionID: String) async throws -> [SessionNote] {
        struct Response: Decodable { let notes: [SessionNote] }
        return try await decode(Response.self, from: notesURL(sessionID), context: "session notes").notes
    }

    public func createSessionNote(
        sessionID: String, body: String, images: [SessionNoteUpload], idempotencyKey: String
    ) async throws -> SessionNote {
        let boundary = "HiBoss-\(UUID().uuidString)"
        var request = authorizedRequest(url: notesURL(sessionID), method: "POST")
        request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var data = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"body\"\r\n\r\n\(body)".utf8)
        for (index, image) in images.enumerated() {
            let ext = image.contentType == "image/gif" ? "gif" : "jpg"
            data.append(Data(("\r\n--\(boundary)\r\nContent-Disposition: form-data; "
                + "name=\"image\"; filename=\"\(index).\(ext)\"\r\n"
                + "Content-Type: \(image.contentType)\r\n\r\n").utf8))
            data.append(image.data)
        }
        data.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = data
        return try decoder.decode(SessionNote.self, from: await validatedData(for: request))
    }

    public func sessionNoteImage(sessionID: String, noteID: String, index: Int) async throws -> Data {
        let url = notesURL(sessionID).appendingPathComponent(noteID)
            .appendingPathComponent("images").appendingPathComponent(String(index))
        return try await validatedData(for: authorizedRequest(url: url, method: "GET"))
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

public struct SessionNoteImage: Codable, Equatable, Sendable {
    public let index: Int
    public let contentType: String
    public let bytes: Int
    enum CodingKeys: String, CodingKey {
        case index, bytes
        case contentType = "content_type"
    }
    public init(index: Int, contentType: String, bytes: Int) {
        self.index = index
        self.contentType = contentType
        self.bytes = bytes
    }
}

public struct SessionNoteUpload: Equatable, Sendable {
    public let data: Data
    public let contentType: String
    public init(data: Data, contentType: String) {
        self.data = data
        self.contentType = contentType
    }
}

public struct SessionNoteReply: Codable, Identifiable, Equatable, Sendable {
    public var id: String { messageID }
    public let messageID: String
    public let body: String
    public let agentName: String
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case body
        case messageID = "message_id", agentName = "agent_name", createdAt = "created_at"
    }

    public init(messageID: String, body: String, agentName: String, createdAt: String) {
        self.messageID = messageID
        self.body = body
        self.agentName = agentName
        self.createdAt = createdAt
    }
}
