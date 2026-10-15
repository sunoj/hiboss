// Reaction normalization and emoji summaries for shared message metadata.
// Exports: MessageReaction and MessageReactionGroup.
// Dependencies: Foundation Codable; malformed array elements are skipped.

import Foundation

public struct MessageReaction: Codable, Hashable, Sendable {
    public enum Actor: String, Codable, Sendable { case boss, agent }

    public let emoji: String
    public let actor: Actor
    public let actorID: String
    /// Absent on legacy reactions, which did not record a timestamp.
    public let createdAt: String?

    public init(emoji: String, actor: Actor, actorID: String, createdAt: String) {
        self.emoji = emoji
        self.actor = actor
        self.actorID = actorID
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case emoji, actor, user
        case actorID = "actor_id"
        case createdAt = "created_at"
        case bossID = "boss_id"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        emoji = try values.decode(String.self, forKey: .emoji)
        if values.contains(.actor) || values.contains(.actorID) {
            actor = try values.decode(Actor.self, forKey: .actor)
            actorID = try values.decode(String.self, forKey: .actorID)
            let timestamp = try values.decode(String.self, forKey: .createdAt)
            guard ISODate.parse(timestamp) != nil else {
                throw DecodingError.dataCorruptedError(forKey: .createdAt, in: values,
                                                       debugDescription: "Invalid reaction timestamp")
            }
            createdAt = timestamp
        } else {
            actor = .boss
            actorID = try values.decodeIfPresent(String.self, forKey: .bossID)
                ?? values.decode(String.self, forKey: .user)
            createdAt = nil
        }
        guard !emoji.isEmpty, !actorID.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .emoji, in: values,
                                                   debugDescription: "Empty reaction identity")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(emoji, forKey: .emoji)
        if createdAt == nil, actor == .boss {
            try values.encode(actorID, forKey: .bossID)
            return
        }
        try values.encode(actor, forKey: .actor)
        try values.encode(actorID, forKey: .actorID)
        try values.encodeIfPresent(createdAt, forKey: .createdAt)
    }

    static func unique(_ reactions: [Self]) -> [Self] {
        var seen: Set<Identity> = []
        return reactions.filter {
            seen.insert(Identity(actor: $0.actor, actorID: $0.actorID, emoji: $0.emoji)).inserted
        }
    }

    static func groups(_ reactions: [Self]) -> [MessageReactionGroup] {
        var groups: [MessageReactionGroup] = []
        for reaction in unique(reactions) {
            if let index = groups.firstIndex(where: { $0.emoji == reaction.emoji }) {
                groups[index].count += 1
                groups[index].bossReacted = groups[index].bossReacted || reaction.actor == .boss
                groups[index].agentReacted = groups[index].agentReacted || reaction.actor == .agent
            } else {
                groups.append(MessageReactionGroup(emoji: reaction.emoji, count: 1,
                    bossReacted: reaction.actor == .boss, agentReacted: reaction.actor == .agent))
            }
        }
        return groups
    }

    private struct Identity: Hashable {
        let actor: Actor
        let actorID: String
        let emoji: String
    }
}

public struct MessageReactionGroup: Equatable, Sendable {
    public let emoji: String
    public internal(set) var count: Int
    public internal(set) var bossReacted: Bool
    public internal(set) var agentReacted: Bool
}

struct FailableReaction: Decodable {
    let value: MessageReaction?
    init(from decoder: Decoder) throws { value = try? MessageReaction(from: decoder) }
}
