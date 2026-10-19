// Named groups of Box items returned by the authenticated Box API.
// Exports BoxCollection with live counts and optional cover metadata.
// Dependencies: Foundation Codable.

import Foundation

public struct BoxCollection: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let bossID: String
    public let bossName: String
    public let name: String
    public let itemCount: Int
    public let coverItemID: String?
    public let createdAt: String
    public let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case bossID = "boss_id"
        case bossName = "boss_name"
        case itemCount = "item_count"
        case coverItemID = "cover_item_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: String, bossID: String, bossName: String, name: String, itemCount: Int,
        coverItemID: String? = nil, createdAt: String, updatedAt: String
    ) {
        self.id = id
        self.bossID = bossID
        self.bossName = bossName
        self.name = name
        self.itemCount = itemCount
        self.coverItemID = coverItemID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
