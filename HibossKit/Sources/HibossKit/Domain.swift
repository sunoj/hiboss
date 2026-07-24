// Domain contracts for message history, streamed options, and boss replies.
// Exports: message models, ConnectionConfig, and BossServing.
// Dependencies: Foundation Codable and async sequence primitives.

import Foundation

public struct MessageID: RawRepresentable, Codable, Hashable, Sendable,
    ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public var description: String { rawValue }
}

public struct MessageMetadata: Codable, Equatable, Sendable {
    public let options: [String]
    public let isExpired: Bool
    /// Label of the option auto-selected on timeout, if the asker marked one.
    public let defaultOption: String?
    /// On a reply's metadata, where the answer came from: "ios", "telegram", etc.
    public let source: String?
    public let content: String?

    enum CodingKeys: String, CodingKey {
        case options
        case isExpired = "options_expired"
        case defaultOption = "default_option"
        case source
        case content
    }

    public init(
        options: [String],
        isExpired: Bool = false,
        defaultOption: String? = nil,
        source: String? = nil,
        content: String? = nil
    ) {
        self.options = options
        self.isExpired = isExpired
        self.defaultOption = defaultOption
        self.source = source
        self.content = content
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        options = try values.decodeIfPresent([String].self, forKey: .options) ?? []
        isExpired = try values.decodeIfPresent(Bool.self, forKey: .isExpired) ?? false
        defaultOption = try values.decodeIfPresent(String.self, forKey: .defaultOption)
        source = try values.decodeIfPresent(String.self, forKey: .source)
        content = try values.decodeIfPresent(String.self, forKey: .content)
    }
}

public struct OptionMessage: Codable, Identifiable, Equatable, Sendable {
    public let id: MessageID
    public let body: String
    public let agentName: String?
    public let metadata: MessageMetadata?
    public let expiresAt: String?
    public let sessionLabel: String?
    public let sessionBranch: String?

    enum CodingKeys: String, CodingKey {
        case id
        case body
        case agentName = "agent_name"
        case metadata
        case expiresAt = "expires_at"
        case sessionLabel = "session_label"
        case sessionBranch = "session_branch"
    }

    public init(
        id: MessageID,
        body: String,
        agentName: String? = nil,
        metadata: MessageMetadata? = nil,
        expiresAt: String? = nil,
        sessionLabel: String? = nil,
        sessionBranch: String? = nil
    ) {
        self.id = id
        self.body = body
        self.agentName = agentName
        self.metadata = metadata
        self.expiresAt = expiresAt
        self.sessionLabel = sessionLabel
        self.sessionBranch = sessionBranch
    }

    public var options: [String] {
        guard metadata?.isExpired != true else { return [] }
        return metadata?.options
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    /// Label of the option that fires automatically on timeout, if marked.
    public var defaultOption: String? { metadata?.defaultOption }

    public var content: String? { metadata?.content }
    public var expirationDate: Date? {
        guard let expiresAt else { return nil }
        return (try? Date(expiresAt, strategy: .iso8601))
            ?? (try? Date(
                expiresAt,
                strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            ))
    }
}

public struct HistoryMessage: Codable, Identifiable, Equatable, Sendable {
    public let id: MessageID
    public let body: String
    public let agentName: String?
    public let direction: String
    public let status: String
    public let priority: String
    public let channel: String?
    public let mode: String?
    /// Parent id when this message is a reply; a decision's answer is the reply
    /// whose `replyTo` equals the decision's id.
    public let replyTo: String?
    public let metadata: MessageMetadata?
    public let expiresAt: String?
    public let createdAt: String
    public let sessionId: String?
    public let sessionLabel: String?
    public let sessionBranch: String?
    public let sessionStatus: String?

    enum CodingKeys: String, CodingKey {
        case id
        case body
        case agentName = "agent_name"
        case direction
        case status
        case priority
        case channel
        case mode
        case replyTo = "reply_to"
        case metadata
        case expiresAt = "expires_at"
        case createdAt = "created_at"
        case sessionId = "session_id"
        case sessionLabel = "session_label"
        case sessionBranch = "session_branch"
        case sessionStatus = "session_status"
    }

    public init(
        id: MessageID,
        body: String,
        agentName: String? = nil,
        direction: String,
        status: String,
        priority: String,
        channel: String? = nil,
        mode: String? = nil,
        replyTo: String? = nil,
        metadata: MessageMetadata? = nil,
        expiresAt: String? = nil,
        createdAt: String,
        sessionId: String? = nil,
        sessionLabel: String? = nil,
        sessionBranch: String? = nil,
        sessionStatus: String? = nil
    ) {
        self.id = id
        self.body = body
        self.agentName = agentName
        self.direction = direction
        self.status = status
        self.priority = priority
        self.channel = channel
        self.mode = mode
        self.replyTo = replyTo
        self.metadata = metadata
        self.expiresAt = expiresAt
        self.createdAt = createdAt
        self.sessionId = sessionId
        self.sessionLabel = sessionLabel
        self.sessionBranch = sessionBranch
        self.sessionStatus = sessionStatus
    }

    public var options: [String] {
        metadata?.options ?? []
    }

    /// Label of the option that fires automatically on timeout, if marked.
    public var defaultOption: String? { metadata?.defaultOption }

    public var content: String? { metadata?.content }

    public var expirationDate: Date? {
        guard let expiresAt else { return nil }
        return (try? Date(expiresAt, strategy: .iso8601))
            ?? (try? Date(
                expiresAt,
                strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            ))
    }
}

public struct HistoryResponse: Codable, Equatable, Sendable {
    public let messages: [HistoryMessage]
    public let total: Int

    public init(messages: [HistoryMessage], total: Int) {
        self.messages = messages
        self.total = total
    }
}

public enum ResolutionStatus: String, Codable, Equatable, Sendable {
    case replied
    case expired
}

public struct OptionResolution: Codable, Equatable, Sendable {
    public let id: MessageID
    public let status: ResolutionStatus
    /// The option text that was chosen, when the decision was answered.
    public let answer: String?
    /// Where the answer came from: "ios", "macos", "telegram", "discord", "api".
    public let source: String?

    enum CodingKeys: String, CodingKey {
        case id, status, answer, source
    }

    public init(id: MessageID, status: ResolutionStatus, answer: String? = nil, source: String? = nil) {
        self.id = id
        self.status = status
        self.answer = answer
        self.source = source
    }

    /// Tolerant decode: older servers omit answer/source.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(MessageID.self, forKey: .id)
        status = try values.decode(ResolutionStatus.self, forKey: .status)
        answer = try values.decodeIfPresent(String.self, forKey: .answer)
        source = try values.decodeIfPresent(String.self, forKey: .source)
    }

    /// Human label for the resolving surface, e.g. "iOS", "Mac", "Telegram".
    public var sourceLabel: String? { resolutionSourceLabel(source) }
}

/// Maps a raw resolution-source tag to a display label. Shared so the option
/// stream and the message-detail view can't drift apart.
public func resolutionSourceLabel(_ source: String?) -> String? {
    switch source?.lowercased() {
    case "ios": return "iOS"
    case "macos", "mac": return "Mac"
    case "telegram": return "Telegram"
    case "discord": return "Discord"
    case "api": return "API"
    case let other?: return other.capitalized
    case nil: return nil
    }
}

public enum BossEvent: Equatable, Sendable {
    case message(OptionMessage)
    case resolved(OptionResolution)
}

public enum ReplyOutcome: Equatable, Sendable {
    case accepted
    case alreadyResolved
}

public struct ConnectionConfig: Equatable, Sendable {
    public let serverURL: URL
    public let bossToken: String

    public init(serverURL: URL, bossToken: String) {
        self.serverURL = serverURL
        self.bossToken = bossToken
    }
}

public protocol BossServing: Sendable {
    func messageStream() async -> AsyncThrowingStream<BossEvent, Error>
    func fetchHistory() async throws -> [HistoryMessage]
    func reply(to messageID: MessageID, with choice: String) async throws -> ReplyOutcome
}
