// Pure content policy for inline history, preserving full text and Unicode boundaries.
// Exports: HistoryReadingContent with long-message detection and a bounded preview.
// Dependencies: Foundation string handling.

import Foundation

struct HistoryReadingContent {
    static let longCharacterCount = 1_200
    static let longLineCount = 14
    static let previewCharacterCount = 600
    static let previewLineCount = 8

    let fullText: String
    let isLong: Bool
    let preview: String

    init(body: String, content: String?) {
        let details = content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        fullText = details.isEmpty ? body : body + "\n\n" + details
        let lines = fullText.components(separatedBy: .newlines)
        isLong = fullText.count > Self.longCharacterCount || lines.count > Self.longLineCount
        let excerpt = lines.prefix(Self.previewLineCount).joined(separator: "\n")
        preview = isLong ? String(excerpt.prefix(Self.previewCharacterCount)) + "…" : fullText
    }
}
