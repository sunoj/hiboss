// Extracts Markdown image references without interpreting fenced or inline code as media.
// Exports MediaMarkdown segments; text fragments retain their original Markdown bytes.
// Dependencies: Foundation and MediaItem; relative document images resolve against their source URL.

import Foundation

enum MediaMarkdown {
    enum Segment {
        case text(String)
        case image(MediaItem)
    }

    static func segments(_ source: String, baseURL: URL? = nil) -> [Segment] {
        var result: [Segment] = []
        var text = ""
        var fence: String?
        for line in source.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let marker = fence {
                if trimmed.hasPrefix(marker) { fence = nil }
                text += line + "\n"
            } else if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence = String(trimmed.prefix(3))
                text += line + "\n"
            } else {
                appendImages(in: line, baseURL: baseURL, text: &text, result: &result)
                text += "\n"
            }
        }
        if !text.isEmpty { result.append(.text(text)) }
        return result
    }

    private static func appendImages(in line: String, baseURL: URL?,
                                     text: inout String, result: inout [Segment]) {
        let pattern = #"`+[^`]*`+|!\[([^\]]*)\]\(\s*(<[^>]+>|[^\s)]+)(?:\s+"([^"]*)")?\s*\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        var cursor = line.startIndex
        for match in regex.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
            guard let range = Range(match.range, in: line),
                  let labelRange = Range(match.range(at: 1), in: line),
                  let urlRange = Range(match.range(at: 2), in: line) else { continue }
            let reference = String(line[urlRange]).trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            guard let url = URL(string: reference, relativeTo: baseURL)?.absoluteURL,
                  ["http", "https", "file"].contains(url.scheme?.lowercased() ?? "") else { continue }
            text += line[cursor..<range.lowerBound]
            if !text.isEmpty { result.append(.text(text)) }
            text = ""
            let caption = Range(match.range(at: 3), in: line).map { String(line[$0]) }
            result.append(.image(MediaItem(url: url, kind: .image,
                                           title: String(line[labelRange]), caption: caption)))
            cursor = range.upperBound
        }
        text += line[cursor...]
    }
}
