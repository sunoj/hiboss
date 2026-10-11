// Keeps short message titles separate from complete Markdown details.
// Exports MessageText and presentation accessors for native message models.
// Dependencies: Foundation Unicode scalar handling; stored source text is unchanged.

import Foundation

public struct MessageText: Equatable, Sendable {
    public static let titleLimit = 144
    public let title: String
    public let content: String?

    public init(body: String, content: String?) {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let details = content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isLong = text.unicodeScalars.count > Self.titleLimit
        title = isLong ? String(text.unicodeScalars.prefix(Self.titleLimit - 1)) + "…" : text
        let full = isLong ? [text, details].filter { !$0.isEmpty }.joined(separator: "\n\n") : details
        self.content = full.isEmpty ? nil : full
    }
}

public extension HistoryMessage {
    var messageText: MessageText { MessageText(body: body, content: content) }
}

public extension OptionMessage {
    var messageText: MessageText { MessageText(body: body, content: content) }
}

public extension SessionEvent {
    var messageContent: String? { payload?.objectValue?["metadata"]?.objectValue?["content"]?.stringValue }
}
