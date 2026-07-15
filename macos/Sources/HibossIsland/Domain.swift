// Domain contracts for streamed option messages and boss replies.
// Exports: MessageID, OptionMessage, ConnectionConfig, and BossServing.
// Dependencies: Foundation Codable and async sequence primitives.

import Foundation

struct MessageID: RawRepresentable, Codable, Hashable, Sendable,
    ExpressibleByStringLiteral, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        self.rawValue = value
    }

    var description: String { rawValue }
}

struct MessageMetadata: Codable, Equatable, Sendable {
    let options: [String]
    let isExpired: Bool

    enum CodingKeys: String, CodingKey {
        case options
        case isExpired = "options_expired"
    }

    init(options: [String], isExpired: Bool = false) {
        self.options = options
        self.isExpired = isExpired
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        options = try values.decodeIfPresent([String].self, forKey: .options) ?? []
        isExpired = try values.decodeIfPresent(Bool.self, forKey: .isExpired) ?? false
    }
}

struct OptionMessage: Codable, Identifiable, Equatable, Sendable {
    let id: MessageID
    let body: String
    let agentName: String?
    let metadata: MessageMetadata?
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case body
        case agentName = "agent_name"
        case metadata
        case expiresAt = "expires_at"
    }

    var options: [String] {
        guard metadata?.isExpired != true else { return [] }
        return metadata?.options
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    var expirationDate: Date? {
        guard let expiresAt else { return nil }
        return (try? Date(expiresAt, strategy: .iso8601))
            ?? (try? Date(
                expiresAt,
                strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            ))
    }
}

enum ResolutionStatus: String, Codable, Equatable, Sendable {
    case replied
    case expired
}

struct OptionResolution: Codable, Equatable, Sendable {
    let id: MessageID
    let status: ResolutionStatus
}

enum BossEvent: Equatable, Sendable {
    case message(OptionMessage)
    case resolved(OptionResolution)
}

enum ReplyOutcome: Equatable, Sendable {
    case accepted
    case alreadyResolved
}

struct ConnectionConfig: Equatable, Sendable {
    let serverURL: URL
    let bossToken: String
}

protocol BossServing: Sendable {
    func messageStream() async -> AsyncThrowingStream<BossEvent, Error>
    func reply(to messageID: MessageID, with choice: String) async throws -> ReplyOutcome
}
