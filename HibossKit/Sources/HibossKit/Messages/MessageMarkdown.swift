// Parses native Markdown blocks while preserving paragraphs and fenced code exactly.
// Exports MessageMarkdownBlock and MessageMarkdown; inline syntax uses Foundation.
// Dependencies: Foundation; HTML is displayed as text rather than executed.

import Foundation

public struct MessageMarkdownBlock: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case paragraph, heading(Int), item(String), quote, code
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
        func flush() {
            if !paragraph.isEmpty {
                result.append(.init(kind: .paragraph, text: paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }
        for line in source.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let marker = fence {
                if trimmed.hasPrefix(marker) {
                    result.append(.init(kind: .code, text: (code ?? []).joined(separator: "\n")))
                    fence = nil
                    code = nil
                } else { code?.append(line) }
            } else if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush()
                fence = String(trimmed.prefix(3))
                code = []
            } else if trimmed.isEmpty {
                flush()
            } else if let block = markedBlock(trimmed) {
                flush()
                result.append(block)
            } else { paragraph.append(line) }
        }
        flush()
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
        return text
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
