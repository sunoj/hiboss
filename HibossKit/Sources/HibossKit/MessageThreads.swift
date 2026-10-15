// Shared history threads and derived decision outcomes for the native clients.
// Exports: MessageThread and ThreadOutcome; replies retain server order.
// Dependencies: Foundation and the HistoryMessage domain contract.

import Foundation

public struct MessageThread: Identifiable, Equatable, Sendable {
    public let message: HistoryMessage
    public let replies: [HistoryMessage]
    /// Every non-root member in chronological order; equal dates retain input order.
    public let entries: [HistoryMessage]

    public var id: MessageID { message.id }
    public var isBoss: Bool { message.direction == "boss_to_agent" }

    public init(message: HistoryMessage, replies: [HistoryMessage] = [],
                entries: [HistoryMessage]? = nil) {
        self.message = message
        self.replies = replies
        self.entries = Self.chronological(entries ?? replies)
    }

    public static func fold(_ history: [HistoryMessage]) -> [MessageThread] {
        let loaded = Dictionary(history.map { ($0.id.rawValue, $0) },
                                uniquingKeysWith: { first, _ in first })
        var members: [String: [HistoryMessage]] = [:]
        for message in history {
            let root = rootID(for: message, loaded: loaded)
            if root != message.id.rawValue { members[root, default: []].append(message) }
        }
        return history.compactMap { message in
            guard rootID(for: message, loaded: loaded) == message.id.rawValue else { return nil }
            let entries = members[message.id.rawValue] ?? []
            return MessageThread(message: message,
                                 replies: entries.filter { $0.direction == "boss_to_agent" },
                                 entries: entries)
        }
    }

    private static func rootID(for message: HistoryMessage,
                               loaded: [String: HistoryMessage]) -> String {
        var current = message
        var visited: Set<String> = []
        while let parent = current.replyTo, let next = loaded[parent] {
            guard visited.insert(current.id.rawValue).inserted else {
                // Cyclic ancestry has no root; retain the message as a standalone row.
                return message.id.rawValue
            }
            current = next
        }
        return current.id.rawValue
    }

    private static func chronological(_ messages: [HistoryMessage]) -> [HistoryMessage] {
        messages.enumerated().sorted {
            let left = replyDate($0.element) ?? .distantPast
            let right = replyDate($1.element) ?? .distantPast
            return left == right ? $0.offset < $1.offset : left < right
        }.map(\.element)
    }

    public var newestReply: HistoryMessage? {
        replies.reduce(nil) { newest, reply in
            guard let newest else { return reply }
            return (Self.replyDate(reply) ?? .distantPast) > (Self.replyDate(newest) ?? .distantPast)
                ? reply : newest
        }
    }

    private static func replyDate(_ reply: HistoryMessage) -> Date? {
        ISODate.parse(reply.createdAt)
            ?? ISODate.parse(reply.createdAt.replacingOccurrences(of: " ", with: "T") + "Z")
    }

    public var outcome: ThreadOutcome { outcome(at: .now) }

    public func outcome(at now: Date) -> ThreadOutcome {
        guard message.direction == "agent_to_boss", !message.options.isEmpty else { return .none }
        if let reply = newestReply {
            return ThreadOutcome(reply: reply, options: message.options,
                                 optionsExpired: message.metadata?.isExpired == true)
        }
        if message.metadata?.isExpired == true {
            let option = message.defaultOption?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .autoSelected(option: option.flatMap { $0.isEmpty ? nil : $0 })
        }
        guard message.status != "expired",
              message.expirationDate.map({ $0 > now }) ?? true else { return .expired }
        guard message.status != "replied" else { return .none }
        return .open
    }
}

public enum ThreadOutcome: Equatable, Sendable {
    case open
    case chosen(option: String, source: String?)
    case autoSelected(option: String?)
    case replied(text: String, source: String?)
    case expired
    case none

    public init(reply: HistoryMessage, options: [String] = [], optionsExpired: Bool = false) {
        let text = reply.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if reply.metadata?.isAutoDefault == true || optionsExpired {
            self = .autoSelected(option: text.isEmpty ? nil : text)
        } else if options.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == text }) {
            self = .chosen(option: text, source: reply.metadata?.source)
        } else {
            self = .replied(text: text, source: reply.metadata?.source)
        }
    }
}
