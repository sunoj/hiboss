// Canonical project identity decoded from boss progress responses.
// Exports ProjectIdentity; depends on Foundation Codable.
import Foundation

public struct ProjectIdentity: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let slug: String
    public let displayName: String
    /// The avatar an agent set with `hiboss project set --avatar`; nil means draw `placeholder`.
    public let avatarURL: URL?

    public var placeholder: ProjectAvatarPlaceholder {
        ProjectAvatarPlaceholder(slug: slug, displayName: displayName)
    }

    enum CodingKeys: String, CodingKey {
        case id, slug
        case displayName = "display_name"
        case avatarURL = "avatar_url"
    }

    public init(id: String, slug: String, displayName: String, avatarURL: URL? = nil) {
        self.id = id
        self.slug = slug
        self.displayName = displayName
        self.avatarURL = avatarURL
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        slug = try values.decode(String.self, forKey: .slug)
        displayName = try values.decode(String.self, forKey: .displayName)
        // Only absolute http(s) avatars; anything else falls back to the placeholder.
        let raw = (try? values.decodeIfPresent(String.self, forKey: .avatarURL)) ?? nil
        avatarURL = raw.flatMap(URL.init(string:)).flatMap { ["http", "https"].contains($0.scheme?.lowercased() ?? "") ? $0 : nil }
    }
}
