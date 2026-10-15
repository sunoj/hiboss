// Plain-text supporting copy for an offered option.
// Exports: OptionDescription; validates entries against MessageMetadata options.
// Dependencies: Foundation Codable and whitespace normalization.

import Foundation

public struct OptionDescription: Codable, Equatable, Sendable {
    public let label: String
    public let text: String

    public init(label: String, text: String) {
        self.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func validated(_ entries: [Self], options: [String]) -> [Self] {
        let offered = Set(options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        var seen = Set<String>()
        return entries.compactMap { entry in
            let normalized = Self(label: entry.label, text: entry.text)
            guard offered.contains(normalized.label), !normalized.text.isEmpty,
                normalized.text.count <= 200, seen.insert(normalized.label).inserted else { return nil }
            return normalized
        }
    }
}

struct FailableOptionDescription: Decodable {
    let value: OptionDescription?

    init(from decoder: Decoder) throws {
        value = try? OptionDescription(from: decoder)
    }
}
