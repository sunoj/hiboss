// Box read filters and editable metadata, preserving omitted versus cleared fields.
// Exports BoxFilters, BoxPatch, BoxFieldUpdate and the list/media/delete service boundary.
// Dependencies: Foundation and BoxItem.

import Foundation

public struct BoxFilters: Sendable {
    public var kind: BoxItem.Kind?
    public var since: String?
    public var project: String?
    public var boss: String?

    public init(
        kind: BoxItem.Kind? = nil, since: String? = nil, project: String? = nil, boss: String? = nil
    ) {
        self.kind = kind
        self.since = since
        self.project = project
        self.boss = boss
    }

    var queryItems: [URLQueryItem] {
        [("kind", kind?.rawValue), ("since", since), ("project", project), ("boss", boss)]
            .compactMap { name, value in value.map { URLQueryItem(name: name, value: $0) } }
    }
}

public enum BoxFieldUpdate: Sendable {
    case unchanged
    case value(String?)
}

public struct BoxPatch: Encodable, Sendable {
    public var note: BoxFieldUpdate
    public var project: BoxFieldUpdate
    public var tags: [String]?

    public init(
        note: BoxFieldUpdate = .unchanged, project: BoxFieldUpdate = .unchanged, tags: [String]? = nil
    ) {
        self.note = note
        self.project = project
        self.tags = tags
    }

    enum CodingKeys: String, CodingKey { case note, project, tags }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        if case let .value(note) = note { try values.encode(note, forKey: .note) }
        if case let .value(project) = project { try values.encode(project, forKey: .project) }
        try values.encodeIfPresent(tags, forKey: .tags)
    }
}

public protocol BoxServing: Sendable {
    func boxItems(filters: BoxFilters, limit: Int, cursor: String?) async throws -> BoxPage
    func downloadBoxMedia(id: String, to destination: URL) async throws
    func deleteBoxItem(id: String, purge: Bool) async throws
}
