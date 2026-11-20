// Answerable decision card and native option buttons using design-v4 role colours.
// Exports: TodayDecisionCard and DecisionChoices; no ranking takes place here.
// Dependencies: SwiftUI, HibossKit AttentionItem, and TodayStyle.

import HibossKit
import SwiftUI

struct TodayDecisionCard: View {
    @Environment(\.projectSessions) private var inventory
    let item: AttentionItem
    let now: Date
    let isSelected: Bool
    let isSubmitting: Bool
    let error: String?
    /// Session text stays selectable. Today still opens the decision from the summary.
    var copyable = false
    let onSelect: () -> Void
    let onChoose: (String) -> Void

    var body: some View {
        let project = item.project(in: inventory)
        VStack(alignment: .leading, spacing: 12) {
            summary(project: project)
            DecisionChoices(item: item, isSubmitting: isSubmitting, onChoose: onChoose)
            if let option = item.defaultOption {
                DecisionDefaultLine(option: option, expiresAt: item.expiresAt, now: now)
            }
            if let error { Text(error).font(.caption).foregroundStyle(TodayStyle.signal) }
        }
        .padding(16)
        .background(TodayStyle.surface, in: cardShape)
        .overlay {
            cardShape.strokeBorder(isSelected ? Color.primary.opacity(0.55) : .clear, lineWidth: isSelected ? 1.5 : 0)
        }
        .accessibilityIdentifier("today.decision.\(item.id.rawValue)")
        .layoutProbe("today.decision.\(item.id.rawValue)")
    }

    /// Surface on Ground already separates a resting card. Signal stays on the
    /// deadline and the count, so selection uses a quiet primary stroke.
    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }

    @ViewBuilder
    private func summary(project: ProjectIdentity) -> some View {
        if copyable {
            summaryStack(project: project)
                .textSelection(.enabled)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("decision.body.copyable")
        } else {
            Button(action: onSelect) {
                summaryStack(project: project).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(L("Open decision"))
            .accessibilityIdentifier("decision.body.button")
        }
    }

    private func summaryStack(project: ProjectIdentity) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ProjectAvatarView(project: project, size: 24)
                Text(verbatim: item.provenance(project: project.displayName))
                    .font(.caption).foregroundStyle(TodayStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                DecisionDeadline(expiresAt: item.expiresAt, now: now)
            }
            Text(verbatim: item.message.messageText.title).font(.headline).foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let content = item.message.messageText.content {
                MessageMarkdownView(content).font(.callout).foregroundStyle(TodayStyle.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

}

struct DecisionDeadline: View {
    let expiresAt: Date?
    let now: Date

    var body: some View {
        if let expiresAt {
            TimelineView(.periodic(from: now, by: 1)) { context in
                Text(AttentionClock.remaining(until: expiresAt, now: context.date))
                    .font(.caption.monospacedDigit()).foregroundStyle(TodayStyle.signal)
            }
        } else {
            Text(L("No deadline")).font(.caption).foregroundStyle(TodayStyle.tertiary)
        }
    }
}
