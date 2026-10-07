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

    enum CodingKeys: String, CodingKey {
        case id, kind, text, url, note, project, tags, source, width, height
        case bossID = "boss_id"
        case bossName = "boss_name"
        case hasMedia = "has_media"
        case mediaType = "media_type"
        case mediaBytes = "media_bytes"
        case durationMs = "duration_ms"
        case createdAt = "created_at"
    }

    public init(
        id: String, bossID: String, bossName: String, kind: Kind,
        text: String? = nil, url: String? = nil, note: String? = nil, project: String? = nil,
        tags: [String] = [], source: Source = .iosShare, hasMedia: Bool = false,
        mediaType: String? = nil, mediaBytes: Int? = nil, width: Int? = nil,
        height: Int? = nil, durationMs: Int? = nil, createdAt: String
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
