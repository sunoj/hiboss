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
        HStack(alignment: .top, spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                AgentAvatarView(name: message.displayName, size: 40, lookupName: message.agentName)
            }
            VStack(alignment: .leading, spacing: 3) {
                RowHeader(name: Text(verbatim: message.displayName), date: message.createdDate)
                Text(verbatim: message.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                if let answer { answerLine(answer) }
                MessageReactions(message: message)
                if let badge = MessageRowBadge.badge(for: message, answerability: answerability) {
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
                RowHeader(name: Text("You"), date: message.createdDate)
                if let agent = message.agentName, !agent.isEmpty {
                    Text("To \(agent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(verbatim: message.body)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                MessageReactions(message: message)
            }
        }
        .padding(.vertical, 4)
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
        if let date {
            RecordedTimeText(date: date)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
