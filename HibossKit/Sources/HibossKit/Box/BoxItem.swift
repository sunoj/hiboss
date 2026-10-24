// Boss-owned reference metadata returned by the authenticated Box API.
// Exports BoxItem and BoxPage; private storage keys are never part of the model.
// Dependencies: Foundation Codable.

import Foundation

public struct BoxItem: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case link, text, image, video, file
    }

    public enum Source: String, Codable, Sendable {
        case iosShare = "ios-share"
        case macShare = "mac-share"
        case macDrop = "mac-drop"
        case cli
    }

    public let id: String
    public let bossID: String
    public let bossName: String
    public let kind: Kind
    public let text: String?
    public let url: String?
    public let note: String?
    public let project: String?
    public let tags: [String]
    public let source: Source
    public let hasMedia: Bool
    public let mediaType: String?
    public let mediaBytes: Int?
    public let width: Int?
    public let height: Int?
    public let durationMs: Int?
    public let createdAt: String
    /// Absent on servers that predate agent writes; every such item came from the boss.
    public let addedBy: BoxAuthor?

    public let liked: Bool
    public let likedAt: String?
    public let collectionIDs: [String]
    /// Absent on servers that predate stored thumbnails; such items have none.
    public let hasThumbnail: Bool

    public var author: BoxAuthor { addedBy ?? .boss }

    enum CodingKeys: String, CodingKey {
        case id, kind, text, url, note, project, tags, source, width, height, liked
        case bossID = "boss_id"
        case bossName = "boss_name"
        case hasMedia = "has_media"
        case mediaType = "media_type"
        case mediaBytes = "media_bytes"
        case durationMs = "duration_ms"
        case createdAt = "created_at"
        case addedBy = "added_by"
        case likedAt = "liked_at"
        case collectionIDs = "collection_ids"
        case hasThumbnail = "has_thumbnail"
    }

    public init(
        id: String, bossID: String, bossName: String, kind: Kind,
        text: String? = nil, url: String? = nil, note: String? = nil, project: String? = nil,
        tags: [String] = [], source: Source = .iosShare, hasMedia: Bool = false,
        mediaType: String? = nil, mediaBytes: Int? = nil, width: Int? = nil,
        height: Int? = nil, durationMs: Int? = nil, createdAt: String, addedBy: BoxAuthor? = nil,
        liked: Bool = false, likedAt: String? = nil, collectionIDs: [String] = [],
        hasThumbnail: Bool = false
    ) {
        self.id = id
        self.bossID = bossID
        self.bossName = bossName
        self.kind = kind
        self.text = text
        self.url = url
        self.note = note
        self.project = project
        self.tags = tags
        self.source = source
        self.hasMedia = hasMedia
        self.mediaType = mediaType
        self.mediaBytes = mediaBytes
        self.width = width
        self.height = height
        self.durationMs = durationMs
        self.createdAt = createdAt
        self.addedBy = addedBy
        self.liked = liked
        self.likedAt = likedAt
        self.collectionIDs = collectionIDs
        self.hasThumbnail = hasThumbnail
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        bossID = try values.decode(String.self, forKey: .bossID)
        bossName = try values.decode(String.self, forKey: .bossName)
        kind = try values.decode(Kind.self, forKey: .kind)
        text = try values.decodeIfPresent(String.self, forKey: .text)
        url = try values.decodeIfPresent(String.self, forKey: .url)
        note = try values.decodeIfPresent(String.self, forKey: .note)
        project = try values.decodeIfPresent(String.self, forKey: .project)
        tags = try values.decode([String].self, forKey: .tags)
        source = try values.decode(Source.self, forKey: .source)
        hasMedia = try values.decode(Bool.self, forKey: .hasMedia)
        mediaType = try values.decodeIfPresent(String.self, forKey: .mediaType)
        mediaBytes = try values.decodeIfPresent(Int.self, forKey: .mediaBytes)
        width = try values.decodeIfPresent(Int.self, forKey: .width)
        height = try values.decodeIfPresent(Int.self, forKey: .height)
        durationMs = try values.decodeIfPresent(Int.self, forKey: .durationMs)
        createdAt = try values.decode(String.self, forKey: .createdAt)
        addedBy = try values.decodeIfPresent(BoxAuthor.self, forKey: .addedBy)
        liked = try values.decodeIfPresent(Bool.self, forKey: .liked) ?? false
        likedAt = try values.decodeIfPresent(String.self, forKey: .likedAt)
        collectionIDs = try values.decodeIfPresent([String].self, forKey: .collectionIDs) ?? []
        hasThumbnail = try values.decodeIfPresent(Bool.self, forKey: .hasThumbnail) ?? false
    }
}

public struct BoxPage: Codable, Equatable, Sendable {
    public let items: [BoxItem]
    public let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
    }

    public init(items: [BoxItem], nextCursor: String? = nil) {
        self.items = items
        self.nextCursor = nextCursor
    }
}
