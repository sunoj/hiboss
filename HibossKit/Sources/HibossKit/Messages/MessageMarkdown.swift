// Parses native Markdown blocks while preserving paragraphs and fenced code exactly.
// Exports MessageMarkdownBlock and MessageMarkdown; a closed ```copy fence becomes a copy block.
// Dependencies: Foundation; HTML is displayed as text rather than executed.

import Foundation

public struct MessageMarkdownBlock: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case paragraph, heading(Int), item(String), quote, code
        /// A closed ```copy fence; the optional label follows `copy` on the opening line.
        case copy(label: String?)
        /// A closed ```hiboss-embed fence holding one card as JSON (see MessageEmbed).
        case embed
    }
    public let kind: Kind
    public let text: String
}

public enum MessageMarkdown {
    public static func blocks(_ source: String) -> [MessageMarkdownBlock] {
        var result: [MessageMarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String]? = nil
        var fence: String?
        var fenceKind = MessageMarkdownBlock.Kind.code
        func flush() {
            if !paragraph.isEmpty {
                result.append(.init(kind: .paragraph, text: paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        for line in normalized.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let marker = fence {
                if trimmed.hasPrefix(marker) {
                    result.append(.init(kind: fenceKind, text: (code ?? []).joined(separator: "\n")))
                    fence = nil
                    code = nil
                } else { code?.append(line) }
            } else if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush()
                fence = String(trimmed.prefix(3))
                fenceKind = kind(forFenceInfo: trimmed.dropFirst(3))
                code = []
            } else if trimmed.isEmpty {
                flush()
            } else if let block = markedBlock(trimmed) {
                flush()
                result.append(block)
            } else { paragraph.append(line) }
        }
        flush()
        // An unclosed fence (a cut preview) never offers copy: its text may be incomplete.
        if let code { result.append(.init(kind: .code, text: code.joined(separator: "\n"))) }
        return result
    }

    public static func inline(_ source: String) -> AttributedString {
        var text = (try? AttributedString(markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(source)
        for run in text.runs {
            if let link = run.link, !["http", "https", "mailto"].contains(link.scheme?.lowercased() ?? "") {
                text[run.range].link = nil
            }
        }
        linkBareURLs(in: &text)
        return text
    }

    private static func kind(forFenceInfo info: Substring) -> MessageMarkdownBlock.Kind {
        let words = info.trimmingCharacters(in: .whitespaces)
        guard let first = words.split(maxSplits: 1, whereSeparator: \.isWhitespace).first else { return .code }
        if first == "hiboss-embed" { return .embed }
        guard first == "copy" else { return .code }
        let label = words.dropFirst(first.count).trimmingCharacters(in: .whitespaces)
        return .copy(label: label.isEmpty ? nil : label)
    }

    private static func markedBlock(_ text: String) -> MessageMarkdownBlock? {
        let hashes = text.prefix { $0 == "#" }.count
        if (1...6).contains(hashes), text.dropFirst(hashes).hasPrefix(" ") {
            return .init(kind: .heading(hashes), text: String(text.dropFirst(hashes + 1)))
        }
        if text.hasPrefix("> ") { return .init(kind: .quote, text: String(text.dropFirst(2))) }
        for prefix in ["- ", "* ", "+ "] where text.hasPrefix(prefix) {
            return .init(kind: .item("•"), text: String(text.dropFirst(2)))
        }
        let digits = text.prefix { $0.isNumber }
        if !digits.isEmpty, text.dropFirst(digits.count).hasPrefix(". ") {
            return .init(kind: .item(String(digits) + "."), text: String(text.dropFirst(digits.count + 2)))
        }
        return nil
    }
}
