// Session-stream event models and the client protocol for history + SSE.
// Exports: SessionEvent, SessionEventsPage, SessionStreamFrame, SessionStreamServing.
// Dependencies: Foundation Codable. Wire format is docs/session-stream-contract.md.

import Foundation

public struct SessionEvent: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let sessionId: String
    public let sequence: Int
    public let kind: String
    public let direction: String?
    public let actorAgentId: String?
    public let actorName: String?
    public let targetAgentId: String?
    public let messageId: String?
    public let source: AnyJSON?
    public let payload: AnyJSON?
    public let raw: AnyJSON?
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, sequence, kind, direction, payload, raw, source
        case sessionId = "session_id"
        case actorAgentId = "actor_agent_id"
        case actorName = "actor_name"
        case targetAgentId = "target_agent_id"
        case messageId = "message_id"
        case createdAt = "created_at"
    }

    public init(
        id: String,
        sessionId: String,
        sequence: Int,
        kind: String,
        direction: String? = nil,
        actorAgentId: String? = nil,
        actorName: String? = nil,
        targetAgentId: String? = nil,
        messageId: String? = nil,
        source: AnyJSON? = nil,
        payload: AnyJSON? = nil,
        raw: AnyJSON? = nil,
        createdAt: String
    ) {
        self.id = id
        self.sessionId = sessionId
        self.sequence = sequence
        self.kind = kind
        self.direction = direction
        self.actorAgentId = actorAgentId
        self.actorName = actorName
        self.targetAgentId = targetAgentId
        self.messageId = messageId
        self.source = source
        self.payload = payload
        self.raw = raw
        self.createdAt = createdAt
    }

    /// Primary text for a transcript row; falls back for unknown kinds.
    public var displayBody: String {
        if let body = payload?.objectValue?["body"]?.stringValue, !body.isEmpty { return body }
        if let summary = payload?.objectValue?["summary"]?.stringValue, !summary.isEmpty {
            return summary
        }
        if let error = payload?.objectValue?["error"]?.stringValue, !error.isEmpty { return error }
        return kind
    }

    public var isRawOutput: Bool {
        kind == "raw" || kind == "tool_result"
    }
}

public struct SessionEventsPage: Codable, Equatable, Sendable {
    public let events: [SessionEvent]
    public let nextAfter: Int?
    public let resync: Bool

    enum CodingKeys: String, CodingKey {
        case events, resync
        case nextAfter = "next_after"
    }

    public init(events: [SessionEvent], nextAfter: Int? = nil, resync: Bool = false) {
        self.events = events
        self.nextAfter = nextAfter
        self.resync = resync
    }
}

public enum SessionStreamFrame: Equatable, Sendable {
    case event(SessionEvent)
    case resync
}

public protocol SessionStreamServing: Sendable {
    func fetchSessionEvents(
        sessionID: String,
        after: Int?,
        limit: Int
    ) async throws -> SessionEventsPage

    func sessionEventStream(
        sessionID: String,
        after: Int
    ) async -> AsyncThrowingStream<SessionStreamFrame, Error>
}

/// Lossless-ish JSON tree for open-shaped `payload` / `source` / `raw` fields.
public enum AnyJSON: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([AnyJSON])
    case object([String: AnyJSON])

    public var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    public var objectValue: [String: AnyJSON]? {
        if case let .object(value) = self { return value }
        return nil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([AnyJSON].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: AnyJSON].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }
}
