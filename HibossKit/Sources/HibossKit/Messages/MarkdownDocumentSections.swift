// Separates pipe tables from native Markdown without interpreting fenced code as tables.
// Exports: MarkdownDocumentSections and MarkdownDocumentTable with column alignment.
// Dependencies: Foundation; other Markdown blocks use MessageMarkdownView.

import Foundation

struct MarkdownDocumentTable: Equatable, Sendable {
    enum Alignment: Equatable, Sendable { case leading, center, trailing }
    let header: [String]
    let alignments: [Alignment]
    let rows: [[String]]
}

enum MarkdownDocumentSection: Equatable, Sendable {
    case text(String), table(MarkdownDocumentTable)
}

enum MarkdownDocumentSections {
    static func parse(_ source: String) -> [MarkdownDocumentSection] {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var result: [MarkdownDocumentSection] = []
        var text: [String] = []
        var fence: String?
        var index = 0
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if let marker = fence {
                if line.hasPrefix(marker) { fence = nil }
            } else if line.hasPrefix("```") || line.hasPrefix("~~~") {
                fence = String(line.prefix(3))
            } else if let (table, next) = table(in: lines, at: index) {
                if !text.isEmpty { result.append(.text(text.joined(separator: "\n"))) }
                text = []
                result.append(.table(table))
                index = next
                continue
            }
            text.append(lines[index])
            index += 1
        }
        if !text.isEmpty { result.append(.text(text.joined(separator: "\n"))) }
        return result
    }

    private static func table(in lines: [String], at index: Int) -> (MarkdownDocumentTable, Int)? {
        guard index + 1 < lines.count, lines[index].contains("|"),
              let alignments = alignments(lines[index + 1]) else { return nil }
        let header = cells(lines[index])
        guard header.count == alignments.count else { return nil }
        var rows: [[String]] = []
        var next = index + 2
        while next < lines.count, lines[next].contains("|") {
            let row = cells(lines[next])
            guard row.count <= header.count else { break }
            rows.append(row + Array(repeating: "", count: header.count - row.count))
            next += 1
        }
        return (.init(header: header, alignments: alignments, rows: rows), next)
    }

    private static func alignments(_ line: String) -> [MarkdownDocumentTable.Alignment]? {
        guard line.contains("|") else { return nil }
        var result: [MarkdownDocumentTable.Alignment] = []
        for cell in cells(line) {
            let dashes = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            guard dashes.count >= 3, dashes.allSatisfy({ $0 == "-" }) else { return nil }
            result.append(cell.hasSuffix(":") ? (cell.hasPrefix(":") ? .center : .trailing) : .leading)
        }
        return result.isEmpty ? nil : result
    }

    private static func cells(_ line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|") && !value.hasSuffix("\\|") { value.removeLast() }
        var result: [String] = []
        var cell = ""
        var escaped = false
        for character in value {
            if escaped {
                if character != "|" { cell.append("\\") }
                cell.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "|" {
                result.append(cell.trimmingCharacters(in: .whitespaces))
                cell = ""
            } else { cell.append(character) }
        }
        if escaped { cell.append("\\") }
        result.append(cell.trimmingCharacters(in: .whitespaces))
        return result
    }
}
