// Who put a Box item in the Box: the boss, or an agent writing on the boss's behalf.
// Exports BoxAuthor, decoded from the server's `added_by` without ever failing a page.
// Dependencies: Foundation Codable.

import Foundation

public enum BoxAuthor: Codable, Equatable, Sendable {
    case boss
    case agent(id: String?, name: String?)

    private enum CodingKeys: String, CodingKey { case kind, id, name }

    /// Any kind other than `boss` is shown as not-the-boss, so an unknown author is never
    /// mistaken for the boss's own material.
    public init(from decoder: Decoder) throws {
        let values = try? decoder.container(keyedBy: CodingKeys.self)
        let kind = try? values?.decodeIfPresent(String.self, forKey: .kind)
        if kind == "boss" {
            self = .boss
            return
        }
        self = .agent(
            id: (try? values?.decodeIfPresent(String.self, forKey: .id)) ?? nil,
            name: (try? values?.decodeIfPresent(String.self, forKey: .name)) ?? nil
        )
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .boss:
            try values.encode("boss", forKey: .kind)
        case let .agent(id, name):
            try values.encode("agent", forKey: .kind)
            try values.encodeIfPresent(id, forKey: .id)
            try values.encodeIfPresent(name, forKey: .name)
        }
    }

    public var isBoss: Bool { self == .boss }
}
