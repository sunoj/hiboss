// Native List row for one History message — Mail-style, no card chrome.
// Exports: HistoryRow with avatar, unread dot, and priority/direction glyphs.
// Dependencies: SwiftUI, HibossKit HistoryMessage, DesignTokens.

import HibossKit
import SwiftUI

struct HistoryRow: View {
    let message: HistoryMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            unreadDot
            avatar
            VStack(alignment: .leading, spacing: 4) {
                header
                Text(message.body)
                    .font(.body)
                    .foregroundStyle(
                        message.isUnreadHistoryMessage ? Color.primary : Color.secondary
                    )
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var unreadDot: some View {
        Circle()
            .fill(message.isUnreadHistoryMessage ? Color.accentColor : Color.clear)
            .frame(width: 8, height: 8)
            .padding(.top, 7)
            .accessibilityLabel(message.isUnreadHistoryMessage ? "Unread" : "Read")
    }

    private var avatar: some View {
        Text(message.historyMonogram)
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.primary)
            .frame(width: 28, height: 28)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(Circle())
            .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(message.historyDisplayName)
                .font(.headline)
                .foregroundStyle(Color.primary)
                .lineLimit(1)

            Image(systemName: message.historyPriorityGlyph)
                .font(.caption)
                .foregroundStyle(priorityColor)
                .accessibilityLabel(message.historyPriorityAccessibilityLabel)

            Image(systemName: message.historyDirectionGlyph)
                .font(.caption)
                .foregroundStyle(Color.secondary)
                .accessibilityLabel(message.historyDirectionAccessibilityLabel)

            Spacer(minLength: 8)

            Text(message.historyTimestamp)
                .font(.caption)
                .monospaced()
                .foregroundStyle(.secondary)
        }
    }

    private var priorityColor: Color {
        switch message.priority.lowercased() {
        case "critical": DesignTokens.Priority.critical
        case "high": DesignTokens.Priority.high
        case "low": DesignTokens.Priority.low
        default: DesignTokens.Priority.normal
        }
    }
}
