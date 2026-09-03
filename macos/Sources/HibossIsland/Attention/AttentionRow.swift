// List row for one attention item — project, asker, wait, urgency.
// Exports: AttentionRow.
// Dependencies: SwiftUI, AttentionItem, DesignTokens.

import SwiftUI

struct AttentionRow: View {
    let item: AttentionItem
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.project)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                trailing
            }
            Text(item.asker)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(item.body)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(2)
            if let content = item.content {
                Text(content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var trailing: some View {
        if let remaining = item.remaining(at: now), let option = item.defaultOption {
            VStack(alignment: .trailing, spacing: 2) {
                Text(remaining)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.primary)
                Text(option)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityLabel(L("Chooses \(option) in \(remaining)"))
        } else if item.band(at: now) == .blocked {
            Text(L("Waiting \(item.waited(at: now))"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        } else if let glyph = priorityGlyph {
            Image(systemName: glyph)
                .font(.caption)
                .foregroundStyle(priorityColor)
                .accessibilityLabel(priorityAccessibilityLabel)
        } else {
            Text(item.waited(at: now))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
    }

    private var priorityGlyph: String? {
        switch item.message.priority.lowercased() {
        case "critical": "exclamationmark.octagon.fill"
        case "high": "exclamationmark.triangle.fill"
        default: nil
        }
    }

    private var priorityColor: Color {
        switch item.message.priority.lowercased() {
        case "critical": DesignTokens.Priority.critical
        case "high": DesignTokens.Priority.high
        default: DesignTokens.Priority.normal
        }
    }

    private var priorityAccessibilityLabel: String {
        switch item.message.priority.lowercased() {
        case "critical": L("Critical priority")
        case "high": L("High priority")
        default: L("Priority")
        }
    }
}
