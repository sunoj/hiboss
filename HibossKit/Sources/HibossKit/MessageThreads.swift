// Shared history threads and derived decision outcomes for the native clients.
// Exports: MessageThread and ThreadOutcome; replies retain server order.
// Dependencies: Foundation and the HistoryMessage domain contract.

import Foundation

public struct MessageThread: Identifiable, Equatable, Sendable {
    public let message: HistoryMessage
    public let replies: [HistoryMessage]

    public var id: MessageID { message.id }
    public var isBoss: Bool { message.direction == "boss_to_agent" }

    public init(message: HistoryMessage, replies: [HistoryMessage] = []) {
        self.message = message
        self.replies = replies
    }

    public static func fold(_ history: [HistoryMessage]) -> [MessageThread] {
        let parents = Set(history.filter { $0.direction != "boss_to_agent" }.map(\.id.rawValue))
        var replies: [String: [HistoryMessage]] = [:]
        for message in history where message.direction == "boss_to_agent" {
            guard let parent = message.replyTo, parents.contains(parent) else { continue }
            replies[parent, default: []].append(message)
        }
        return history.compactMap { message in
            if message.direction == "boss_to_agent",
               let parent = message.replyTo, parents.contains(parent) { return nil }
            return MessageThread(message: message, replies: replies[message.id.rawValue] ?? [])
        }
    }

    public var newestReply: HistoryMessage? {
        replies.reduce(nil) { newest, reply in
            guard let newest else { return reply }
            return (ISODate.parse(reply.createdAt) ?? .distantPast)
                > (ISODate.parse(newest.createdAt) ?? .distantPast)
                ? reply : newest
        }
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
