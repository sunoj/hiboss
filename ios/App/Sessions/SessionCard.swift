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
        VStack(alignment: .leading, spacing: 10) {
            topRow
            metaRow
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
    }

    private var topRow: some View {
        HStack(spacing: 9) {
            Circle().fill(statusColor).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if let agent = group.agentName {
                    Text(agent)
                        .font(.hbMonoSmall)
                        .foregroundStyle(Theme.ink3)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if group.pendingCount > 0 { pendingPill }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.ink4)
        }
    }

    private var pendingPill: some View {
        Text("\(group.pendingCount) pending")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(PriorityColor.criticalText)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(PriorityColor.critical.opacity(0.14))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(PriorityColor.critical.opacity(0.4), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var metaRow: some View {
        HStack(spacing: 10) {
            if !statusLabel.isEmpty { chip(icon: "circle.fill", text: statusLabel, tint: statusColor) }
            chip(icon: "bubble.left", text: "\(group.messages.count)", tint: Theme.ink3)
            if let last = group.lastActivity {
                chip(icon: "clock", text: RelativeTime.short(from: last), tint: Theme.ink3)
            }
            Spacer(minLength: 0)
        }
    }

    private func chip(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9)).foregroundStyle(tint)
            Text(text).font(.hbMonoSmall).foregroundStyle(Theme.ink3)
        }
    }

    private var statusLabel: String {
        guard !group.statusWord.isEmpty else { return "" }
        return group.statusWord.capitalized
    }

    private var statusColor: Color {
        switch group.statusWord {
        case "working": Theme.positive
        case "waiting", "blocked": Theme.warn
        default: Theme.ink4
        }
    }
}
