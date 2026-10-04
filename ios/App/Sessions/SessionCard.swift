// One session summary card: status, agent, branch, pending + activity.
// Exports: SessionCard rendering a SessionGroup; SessionGroup summary helpers.
// Dependencies: SwiftUI, HibossKit SessionGroup, SessionStatusStyle, theme tokens. Accessibility
// sizes stack, never truncate.

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

struct SessionCard: View {
    let group: SessionGroup
    @Environment(\.dynamicTypeSize) private var typeSize

    /// At accessibility sizes every row stacks and wraps instead of cutting words off.
    private var stacked: Bool { typeSize.isAccessibilitySize }
    private var lineLimit: Int? { stacked ? nil : 1 }

    private var rowLayout: AnyLayout {
        stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusRow
            titleRow
            metaRow
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }

    private var statusRow: some View {
        rowLayout {
            if let statusStyle {
                Label(statusStyle.label, systemImage: statusStyle.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(statusStyle.tint)
                    .symbolRenderingMode(.hierarchical)
                    .lineLimit(lineLimit)
            }
            if !stacked { Spacer(minLength: 8) }
            if let last = group.lastActivity {
                Text(verbatim: RelativeTime.short(from: last))
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(lineLimit)
            }
        }
    }

    private var titleRow: some View {
        rowLayout {
            Text(verbatim: group.localizedLabel)
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .lineLimit(lineLimit)
            if group.pendingCount > 0 { pendingBadge }
            if !stacked { Spacer(minLength: 0) }
        }
    }

    private var pendingBadge: some View {
        Text("\(group.pendingCount) pending")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.negative)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.negative.opacity(0.15), in: Capsule())
    }

    private var metaRow: some View {
        (stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 12))) {
            if let agent = group.agentName, !agent.isEmpty { chip("person", agent, Theme.ink2) }
            if let branch = group.branch, !branch.isEmpty {
                chip("arrow.triangle.branch", branch, Theme.ink2)
            }
            chip("bubble.left", group.messages.count.formatted(), Theme.ink2)
            if !stacked { Spacer(minLength: 0) }
        }
        .font(.caption)
        .foregroundStyle(Theme.ink2)
        .lineLimit(lineLimit)
    }

    private func chip(_ icon: String, _ text: String, _ tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Image(systemName: icon).font(.caption2).foregroundStyle(tint)
            Text(verbatim: text).fixedSize(horizontal: false, vertical: stacked)
        }
    }

    private var statusStyle: SessionStatusStyle? {
        SessionStatusStyle(word: group.statusWord)
    }
}
