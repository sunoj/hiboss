// Progress-feed domain models and the client protocol for GET/DELETE /api/progress.
// Exports: ProgressPost, ProgressMedia, ProgressFeedPage, ProgressProject, ProgressServing.
// Dependencies: Foundation Codable. Wire format is docs/progress-feed-contract.md.

import Foundation

public struct ProgressMedia: Codable, Equatable, Sendable, Identifiable {
    public var id: String { url }

    public let url: String
    public let kind: Kind
    public let contentType: String
    public let size: Int
    public let width: Int?
    public let height: Int?
    public let durationMs: Int?
    public let posterUrl: String?
    public let alt: String?

    public enum Kind: String, Codable, Sendable {
        case image
        case video
    }

    enum CodingKeys: String, CodingKey {
        case url, kind, size, width, height, alt
        case contentType = "content_type"
        case durationMs = "duration_ms"
        case posterUrl = "poster_url"
    }

    public init(
        url: String,
        kind: Kind,
        contentType: String,
        size: Int,
        width: Int? = nil,
        height: Int? = nil,
        durationMs: Int? = nil,
        posterUrl: String? = nil,
        alt: String? = nil
    ) {
        self.url = url
        self.kind = kind
        self.contentType = contentType
        self.size = size
        self.width = width
        self.height = height
        self.durationMs = durationMs
        self.posterUrl = posterUrl
        self.alt = alt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        url = try values.decode(String.self, forKey: .url)
        kind = try values.decode(Kind.self, forKey: .kind)
        contentType = try values.decode(String.self, forKey: .contentType)
        size = try values.decode(Int.self, forKey: .size)
        width = try values.decodeIfPresent(Int.self, forKey: .width)
        height = try values.decodeIfPresent(Int.self, forKey: .height)
        durationMs = try values.decodeIfPresent(Int.self, forKey: .durationMs)
        posterUrl = try values.decodeIfPresent(String.self, forKey: .posterUrl)
        alt = try values.decodeIfPresent(String.self, forKey: .alt)
    }
}

public struct ProgressPost: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let project: String
    public let agentId: String
    public let agentName: String
    public let sessionId: String?
    public let body: String
    public let media: [ProgressMedia]
    public let tags: [String]
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, project, body, media, tags
        case agentId = "agent_id"
        case agentName = "agent_name"
        case sessionId = "session_id"
        case createdAt = "created_at"
    }

    public init(
        id: String,
        project: String,
        agentId: String,
        agentName: String,
        sessionId: String? = nil,
        body: String,
        media: [ProgressMedia] = [],
        tags: [String] = [],
        createdAt: String
    ) {
        self.id = id
        self.project = project
        self.agentId = agentId
        self.agentName = agentName
        self.sessionId = sessionId
        self.body = body
        self.media = media
        self.tags = tags
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        project = try values.decode(String.self, forKey: .project)
        agentId = try values.decode(String.self, forKey: .agentId)
        agentName = try values.decodeIfPresent(String.self, forKey: .agentName) ?? ""
        sessionId = try values.decodeIfPresent(String.self, forKey: .sessionId)
        body = try values.decode(String.self, forKey: .body)
        media = try values.decodeIfPresent([ProgressMedia].self, forKey: .media) ?? []
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
        createdAt = try values.decode(String.self, forKey: .createdAt)
    }
}

public struct ProgressFeedPage: Codable, Equatable, Sendable {
    public let posts: [ProgressPost]
    public let nextCursor: ProgressCursor?

    enum CodingKeys: String, CodingKey {
        case posts
        case nextCursor = "next_cursor"
    }

    public init(posts: [ProgressPost], nextCursor: ProgressCursor? = nil) {
        self.posts = posts
        self.nextCursor = nextCursor
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        posts = try values.decodeIfPresent([ProgressPost].self, forKey: .posts) ?? []
        nextCursor = try values.decodeIfPresent(ProgressCursor.self, forKey: .nextCursor)
    }
}

public struct ProgressCursor: Codable, Equatable, Sendable {
    public let createdAt: String
    public let id: String

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
    }

    public init(createdAt: String, id: String) {
        self.createdAt = createdAt
        self.id = id
    }
}

public struct ProgressProject: Codable, Equatable, Sendable, Identifiable {
    public var id: String { project }

    public let project: String
    public let count: Int
    public let lastPostAt: String
    public let agentId: String

    enum CodingKeys: String, CodingKey {
        case project, count
        case lastPostAt = "last_post_at"
        case agentId = "agent_id"
    }

    public init(project: String, count: Int, lastPostAt: String, agentId: String) {
        self.project = project
        self.count = count
        self.lastPostAt = lastPostAt
        self.agentId = agentId
    }
}

struct ProgressProjectsResponse: Decodable, Sendable {
    let projects: [ProgressProject]
}

public protocol ProgressServing: Sendable {
    func progressFeed(project: String?, limit: Int, before: ProgressCursor?) async throws -> ProgressFeedPage
    func progressProjects() async throws -> [ProgressProject]
    func deleteProgressPost(id: String) async throws
}

extension HibossAPI: ProgressServing {}
