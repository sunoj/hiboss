// Native List row for one History message — Mail-style, no card chrome.
// Exports: HistoryRow with avatar, unread dot, and priority/direction glyphs.
// Dependencies: SwiftUI, HibossKit HistoryMessage, DesignTokens.

import HibossKit
import SwiftUI

struct HistoryRow: View {
    let message: HistoryMessage
    var onChoose: ((String) -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            unreadDot
            avatar
            VStack(alignment: .leading, spacing: 6) {
                header
                Text(message.body)
                    .font(.body)
                    .foregroundStyle(
                        message.isUnreadHistoryMessage ? Color.primary : Color.secondary
                    )
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                if !message.options.isEmpty {
                    optionRow
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var optionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(message.options, id: \.self) { option in
                    if message.isBlockingHistoryMessage {
                        Button(option) { onChoose?(option) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    } else {
                        Text(option)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    private var unreadDot: some View {
        Circle()
            .fill(message.isUnreadHistoryMessage ? Color.accentColor : Color.clear)
            .frame(width: 8, height: 8)
            .padding(.top, 7)
            .accessibilityLabel(message.isUnreadHistoryMessage ? "Unread" : "Read")
    }

    /// Filled with `.quaternary` rather than `controlBackgroundColor`: the latter resolves to
    /// the same white as the list itself in light appearance, leaving the monogram floating
    /// with no visible tile. This stays a step off the background in both appearances.
    private var avatar: some View {
        Text(message.historyMonogram)
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.secondary)
            .frame(width: 28, height: 28)
            .background(.quaternary, in: Circle())
            .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(message.historyDisplayName)
                .font(.headline)
                .foregroundStyle(Color.primary)
                .lineLimit(1)

            if let glyph = message.historyPriorityGlyph {
                Image(systemName: glyph)
                    .font(.caption)
                    .foregroundStyle(priorityColor)
                    .accessibilityLabel(message.historyPriorityAccessibilityLabel)
            }

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
