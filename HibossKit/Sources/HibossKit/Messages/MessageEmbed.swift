// Decodes one hiboss-embed card (a Discord-style embed) and lays its fields out in rows.
// Exports MessageEmbed; text values are Markdown, colour is 0xRRGGBB, time is ISO 8601.
// Dependencies: Foundation only; MessageEmbedCard draws it.

import Foundation

public struct MessageEmbed: Decodable, Equatable, Sendable {
    public struct Field: Decodable, Equatable, Sendable {
        public let name: String
        public let value: String
        public let inline: Bool

        public init(name: String, value: String, inline: Bool) {
            self.name = name
            self.value = value
            self.inline = inline
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
            value = try values.decodeIfPresent(String.self, forKey: .value) ?? ""
            inline = try values.decodeIfPresent(Bool.self, forKey: .inline) ?? false
        }

        private enum CodingKeys: String, CodingKey { case name, value, inline }
    }

    /// A text-only block (no card): the sender's message text or notes around the cards.
    public let text: String?
    public let color: Int?
    public let title: String?
    public let url: URL?
    public let author: String?
    public let description: String?
    public let fields: [Field]
    public let image: URL?
    public let thumbnail: URL?
    public let footer: String?
    public let timestamp: Date?

    public var isTextOnly: Bool {
        text != nil && title == nil && url == nil && author == nil && description == nil && fields.isEmpty
            && image == nil && thumbnail == nil && footer == nil && timestamp == nil
    }

    /// Nil for text that is not a card, so the caller can fall back to plain code.
    public static func decode(_ text: String) -> MessageEmbed? {
        try? JSONDecoder().decode(MessageEmbed.self, from: Data(text.utf8))
    }

    /// Discord's layout: consecutive inline fields share a row, at most three; others stand alone.
    public var fieldRows: [[Field]] {
        var rows: [[Field]] = []
        for field in fields {
            if field.inline, let last = rows.last, last.count < 3, last.allSatisfy(\.inline) {
                rows[rows.count - 1].append(field)
            } else {
                rows.append([field])
            }
        }
        return rows
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let string = { (key: CodingKeys) in (try? values.decodeIfPresent(String.self, forKey: key)) ?? nil }
        let link = { (key: CodingKeys) in string(key).flatMap(Self.webURL) }
        text = string(.text)
        color = (try? values.decodeIfPresent(Int.self, forKey: .color)) ?? nil
        title = string(.title)
        url = link(.url)
        author = string(.author)
        description = string(.description)
        fields = (try? values.decodeIfPresent([Field].self, forKey: .fields)) ?? []
        image = link(.image)
        thumbnail = link(.thumbnail)
        footer = string(.footer)
        timestamp = string(.timestamp).flatMap { ISO8601DateFormatter.withFraction.date(from: $0)
            ?? ISO8601DateFormatter().date(from: $0) }
    }

    private static func webURL(_ text: String) -> URL? {
        guard let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    private enum CodingKeys: String, CodingKey {
        case text, color, title, url, author, description, fields, image, thumbnail, footer, timestamp
    }
}

private extension ISO8601DateFormatter {
    nonisolated(unsafe) static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
