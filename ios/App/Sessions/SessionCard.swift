// One session summary card: status, agent, branch, pending + activity.
// Exports: SessionCard rendering a SessionGroup; SessionGroup summary helpers.
// Dependencies: SwiftUI, HibossKit SessionGroup, theme tokens.

import HibossKit
import SwiftUI

extension SessionGroup {
    /// Live decisions in this session still waiting on the boss.
    var pendingCount: Int { messages.filter(\.isPendingDecision).count }

    /// Newest activity timestamp across the session's messages.
    var lastActivity: Date? { messages.compactMap(\.createdDate).max() }

    /// Normalised status word, lowercased, empty when unknown.
    var statusWord: String {
        status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }
}

struct SessionCard: View {
    let group: SessionGroup

    var body: some View {
        HStack(spacing: 11) {
            Circle().fill(statusColor).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(group.label)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if group.pendingCount > 0 { pendingBadge }
                }
                metaRow
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var pendingBadge: some View {
        Text("\(group.pendingCount) pending")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.red)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.red.opacity(0.15), in: Capsule())
    }

    private var metaRow: some View {
        HStack(spacing: 12) {
            if !statusLabel.isEmpty { chip("circle.fill", statusLabel, statusColor) }
            if let agent = group.agentName, !agent.isEmpty { chip("person", agent, .secondary) }
            if let branch = group.branch, !branch.isEmpty {
                chip("arrow.triangle.branch", branch, .secondary)
            }
            chip("bubble.left", "\(group.messages.count)", .secondary)
            if let last = group.lastActivity {
                chip("clock", RelativeTime.short(from: last), .secondary)
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private func chip(_ icon: String, _ text: String, _ tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.caption2).foregroundStyle(tint)
            Text(text)
        }
    }

    private var statusLabel: String {
        group.statusWord.isEmpty ? "" : group.statusWord.capitalized
    }

    private var statusColor: Color {
        switch group.statusWord {
        case "working": .green
        case "waiting", "blocked": .orange
        default: .secondary
        }
    }
}
