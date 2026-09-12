// Canonical project identity decoded from boss progress responses.
// Exports ProjectIdentity; depends on Foundation Codable.
import Foundation

public struct ProjectIdentity: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let slug: String
    public let displayName: String

    enum CodingKeys: String, CodingKey {
        case id, slug
        case displayName = "display_name"
    }

    public init(id: String, slug: String, displayName: String) {
        self.id = id
        self.slug = slug
        self.displayName = displayName
    }
}
