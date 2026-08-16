// One session summary card: status, agent, branch, pending + activity.
// Exports: SessionCard rendering a SessionGroup; SessionGroup summary helpers.
// Dependencies: SwiftUI, HibossKit SessionGroup, theme tokens.

import HibossKit
import SwiftUI

extension SessionGroup {
    /// Live decisions in this session still waiting on the boss.
    var pendingCount: Int { messages.filter(\.isPendingDecision).count }

    var localizedLabel: String {
        id == SessionGrouping.directSessionID ? String(localized: "Direct") : label
    }

    /// Newest activity timestamp across the session's messages.
    var lastActivity: Date? { messages.compactMap(\.createdDate).max() }

    /// Normalised status word, lowercased, empty when unknown.
    var statusWord: String {
        status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }
}

/// Localized status word, glyph, and tint for a session board card.
struct SessionStatusStyle {
    let label: String
    let icon: String
    let tint: Color

    init?(word: String) {
        guard !word.isEmpty else { return nil }
        switch word {
        case "working":
            label = String(localized: "Working")
            icon = "ellipsis.circle.fill"
            tint = .green
        case "blocked":
            label = String(localized: "Blocked")
            icon = "exclamationmark.octagon.fill"
            tint = .red
        case "waiting":
            label = String(localized: "Waiting")
            icon = "clock.fill"
            tint = .orange
        case "idle":
            label = String(localized: "Idle")
            icon = "pause.circle.fill"
            tint = .secondary
        case "completed":
            label = String(localized: "Completed")
            icon = "checkmark.circle.fill"
            tint = .secondary
        default:
            label = word.capitalized
            icon = "circle.fill"
            tint = .secondary
        }
    }
}

struct SessionCard: View {
    let group: SessionGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusRow
            titleRow
            metaRow
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(alignment: .leading) { statusStripe }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var statusStripe: some View {
        if let tint = statusStyle?.tint {
            UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20)
                .fill(tint)
                .frame(width: 4)
                .accessibilityHidden(true)
        }
    }

    private var statusRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let statusStyle {
                Label(statusStyle.label, systemImage: statusStyle.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(statusStyle.tint)
                    .symbolRenderingMode(.hierarchical)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let last = group.lastActivity {
                Text(RelativeTime.short(from: last))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(group.localizedLabel)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
            if group.pendingCount > 0 { pendingBadge }
            Spacer(minLength: 0)
        }
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
            if let agent = group.agentName, !agent.isEmpty { chip("person", agent, .secondary) }
            if let branch = group.branch, !branch.isEmpty {
                chip("arrow.triangle.branch", branch, .secondary)
            }
            chip("bubble.left", "\(group.messages.count)", .secondary)
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

    private var statusStyle: SessionStatusStyle? {
        SessionStatusStyle(word: group.statusWord)
    }
}
