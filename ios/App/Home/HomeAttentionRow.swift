// "Needs you" attention list with deep-links into decision / session detail.
// Exports: HomeAttentionSection and HomeAttentionRow.
// Dependencies: SwiftUI, HibossKit HomeAttentionItem, Theme tokens.

import HibossKit
import SwiftUI

struct HomeAttentionSection: View {
    let items: [HomeAttentionItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Needs you")
                .font(.hbH3)
                .foregroundStyle(Theme.ink)
            if items.isEmpty {
                Label("You're all clear", systemImage: "checkmark.circle")
                    .font(.hbCallout)
                    .foregroundStyle(Theme.ink3)
            } else {
                ForEach(items) { item in
                    attentionLink(item)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func attentionLink(_ item: HomeAttentionItem) -> some View {
        switch item.kind {
        case .decision:
            if let raw = item.messageId, !raw.isEmpty {
                NavigationLink(value: MessageID(rawValue: raw)) {
                    HomeAttentionRow(item: item)
                }
                .buttonStyle(.plain)
            } else {
                HomeAttentionRow(item: item)
            }
        case .session:
            if let sessionId = item.sessionId, !sessionId.isEmpty {
                NavigationLink(value: SessionRoute(id: sessionId, label: sessionLabel(for: item, fallback: sessionId))) {
                    HomeAttentionRow(item: item)
                }
                .buttonStyle(.plain)
            } else {
                HomeAttentionRow(item: item)
            }
        }
    }

    private func sessionLabel(for item: HomeAttentionItem, fallback: String) -> String {
        if let label = item.sessionLabel, !label.isEmpty { return label }
        return String(fallback.prefix(8))
    }
}

struct HomeAttentionRow: View {
    let item: HomeAttentionItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.hbBodyStrong)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.hbCaption)
                    .foregroundStyle(Theme.ink3)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.hbCaption)
                .foregroundStyle(Theme.ink4)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch item.kind {
        case .decision: return item.mode == "blocking" ? "exclamationmark.octagon.fill" : "hand.raised.fill"
        case .session: return item.status == "blocked" ? "exclamationmark.octagon.fill" : "clock.fill"
        }
    }

    private var tint: Color {
        switch item.kind {
        case .decision:
            return item.mode == "blocking" || item.priority == "high" || item.priority == "critical"
                ? Theme.warn : Theme.ink2
        case .session:
            return item.status == "blocked" ? Theme.negative : Theme.warn
        }
    }

    private var title: String {
        switch item.kind {
        case .decision: return item.body ?? String(localized: "Pending decision")
        case .session: return item.statusText ?? item.sessionLabel ?? String(localized: "Session needs you")
        }
    }

    private var subtitle: String {
        var parts = [item.project]
        if let label = item.sessionLabel, !label.isEmpty { parts.append(label) }
        if item.kind == .decision, let mode = item.mode { parts.append(mode) }
        if item.kind == .session, let status = item.status { parts.append(status) }
        return parts.joined(separator: " · ")
    }
}
