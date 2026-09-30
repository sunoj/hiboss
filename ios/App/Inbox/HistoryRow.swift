// Messages list rows, following iOS Messages: agent rows and the boss's own rows.
// Exports: HistoryRow (agent message + folded boss answer) and BossHistoryRow.
// Dependencies: SwiftUI, HibossKit, MessageRowBadge.

import HibossKit
import SwiftUI

struct HistoryRow: View {
    let message: HistoryMessage
    /// The boss's answer to this message, shown on the row instead of as its own row.
    var answer: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                Text(verbatim: message.avatarInitials)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .background(Color(.tertiarySystemFill), in: Circle())
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                RowHeader(name: Text(verbatim: message.displayName), time: message.relativeCreatedAt)
                Text(verbatim: message.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                if let answer { answerLine(answer) }
                if let badge = MessageRowBadge.badge(for: message) {
                    Text(verbatim: badge.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(badge.tint)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func answerLine(_ answer: String) -> some View {
        Group {
            if message.isDecision {
                Text("You answered: \(answer)")
            } else {
                Text("You replied: \(answer)")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.primary)
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
    }
}

/// A boss-authored message with no parent in the list: the boss's own row, never
/// under the agent's name or avatar.
struct BossHistoryRow: View {
    let message: HistoryMessage
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.body)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 40, height: 40)
                    .background(Theme.surface2, in: Circle())
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                RowHeader(name: Text("You"), time: message.relativeCreatedAt)
                if let agent = message.agentName, !agent.isEmpty {
                    Text("To \(agent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(verbatim: message.body)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// Name and time side by side; stacked at accessibility sizes so the name never truncates.
private struct RowHeader: View {
    let name: Text
    let time: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                name.font(.headline).foregroundStyle(.primary)
                timeText
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                name.font(.headline).foregroundStyle(.primary).lineLimit(1)
                Spacer(minLength: 4)
                timeText
            }
        }
    }

    @ViewBuilder private var timeText: some View {
        if !time.isEmpty {
            Text(verbatim: time)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
