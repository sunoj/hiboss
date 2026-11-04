// Messages list rows, following iOS Messages: agent rows and the boss's own rows.
// Exports: HistoryRow (agent message + folded boss answer) and BossHistoryRow.
// Dependencies: SwiftUI, HibossKit, MessageRowBadge.

import HibossKit
import SwiftUI

struct HistoryRow: View {
    let message: HistoryMessage
    /// The boss's answer to this message, shown on the row instead of as its own row.
    var answer: String?
    var answerability: DecisionAnswerability = .closed
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            if !dynamicTypeSize.isAccessibilitySize {
                AgentAvatarView(name: message.displayName, size: AvatarSize.row,
                                lookupName: message.agentName)
            }
            VStack(alignment: .leading, spacing: Space.xxs) {
                RowHeader(name: Text(verbatim: message.displayName), date: message.createdDate)
                Text(verbatim: message.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: Space.xs) {
                    if let answer { answerLine(answer) }
                    if let badge = MessageRowBadge.badge(for: message, answerability: answerability) {
                        Text(verbatim: badge.title).font(.caption.weight(.semibold))
                            .foregroundStyle(badge.tint).lineLimit(1)
                    }
                }
                MessageReactions(message: message)
            }
        }
        .padding(.vertical, Space.xxs)
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
        .font(.caption)
        .foregroundStyle(.primary)
        .lineLimit(1)
    }
}

/// A boss-authored message with no parent in the list: the boss's own row, never
/// under the agent's name or avatar.
struct BossHistoryRow: View {
    let message: HistoryMessage
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.body)
                    .foregroundStyle(Theme.accent)
                    .frame(width: AvatarSize.row, height: AvatarSize.row)
                    .background(Theme.surface2, in: Circle())
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: Space.xxs) {
                RowHeader(name: Text("You"), date: message.createdDate)
                if let agent = message.agentName, !agent.isEmpty {
                    Text("To \(agent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(verbatim: message.body)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                MessageReactions(message: message)
            }
        }
        .padding(.vertical, Space.xxs)
        .contentShape(Rectangle())
    }
}

/// Name and time side by side; stacked at accessibility sizes so the name never truncates.
private struct RowHeader: View {
    let name: Text
    let date: Date?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Space.xxs) {
                name.font(.headline).foregroundStyle(.primary)
                timeText
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                name.font(.headline).foregroundStyle(.primary).lineLimit(1)
                Spacer(minLength: Space.xxs)
                timeText
            }
        }
    }

    @ViewBuilder private var timeText: some View {
        if let date {
            RecordedTimeText(date: date)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
