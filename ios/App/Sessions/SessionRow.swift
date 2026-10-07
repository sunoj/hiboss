// Native session list summary: session, status, agent and latest activity.
// Exports: SessionRow and SessionGroup summary helpers for Activity.
// Dependencies: SwiftUI, HibossKit SessionGroup, SessionStatusStyle and Theme.

import HibossKit
import SwiftUI

extension SessionGroup {
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

struct SessionRow: View {
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
            titleRow
            statusRow
            if let agent = group.agentName, !agent.isEmpty {
                Text(verbatim: agent).font(.caption).foregroundStyle(Theme.ink2)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var statusRow: some View {
        rowLayout {
            if let statusStyle {
                Label {
                    Text(verbatim: statusStyle.label)
                } icon: {
                    Image(systemName: statusStyle.icon)
                }
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
            if !stacked { Spacer(minLength: 0) }
        }
    }

    private var statusStyle: SessionStatusStyle? {
        SessionStatusStyle(word: group.statusWord)
    }
}
