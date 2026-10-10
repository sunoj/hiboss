// The placeholder a project shows until an agent sets its avatar: a stable colour and initial.
// Exports: ProjectAvatarPlaceholder; both apps draw it, so a project looks the same everywhere.
// Dependencies: Foundation only; the hash is FNV-1a so it never changes between launches.

import Foundation

public struct ProjectAvatarPlaceholder: Equatable, Sendable {
    /// Named tints from the v4 brand palette, in a fixed order; apps map them to colours.
    public enum Tint: Int, CaseIterable, Sendable {
        case sky, lagoon, sand, palm, coral, violet, slate, amber
    }

    public let tint: Tint
    /// The first letter of the project's display name, uppercased; "?" when there is none.
    public let initial: String

    /// `slug` decides colour (stable across renames of the display name).
    public init(slug: String, displayName: String? = nil) {
        let hash = Self.fnv1a(slug.lowercased())
        tint = Tint(rawValue: Int(hash % UInt64(Tint.allCases.count))) ?? .sky
        let name = (displayName?.isEmpty == false ? displayName : slug) ?? slug
        initial = name.first(where: { $0.isLetter || $0.isNumber }).map { String($0).uppercased() } ?? "?"
    }

    static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}
