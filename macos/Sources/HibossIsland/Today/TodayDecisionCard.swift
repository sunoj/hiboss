// Answerable decision card and native option buttons using design-v4 role colours.
// Exports: TodayDecisionCard (long details collapse to a preview); no ranking takes place here.
// Dependencies: SwiftUI, HibossKit AttentionItem, and TodayStyle.

import HibossKit
import SwiftUI

struct TodayDecisionCard: View {
    @Environment(\.projectSessions) private var inventory
    let item: AttentionItem
    let now: Date
    let isSubmitting: Bool
    let error: String?
    /// Session text stays selectable. Today still opens the decision from the summary.
    var copyable = false
    let onSelect: () -> Void
    let onChoose: (String) -> Void
    @State private var detailsExpanded = false

    var body: some View {
        let project = item.project(in: inventory)
        VStack(alignment: .leading, spacing: 12) {
            summary(project: project)
            if let content = item.message.messageText.content {
                // Outside the summary button, so the toggle is not a button inside a button.
                OptionMessageDetails(text: content, isExpanded: $detailsExpanded,
                    unitsPerLine: Self.detailsUnitsPerLine, previewLineCount: Self.detailsPreviewLines, textColor: TodayStyle.secondary,
                    toggleColor: TodayStyle.secondary, identifier: "decision.details", cards: true)
                    .textSelection(.enabled)
            }
            DecisionChoices(item: item, isSubmitting: isSubmitting, onChoose: onChoose)
            if let option = item.defaultOption {
                DecisionDefaultLine(option: option, expiresAt: item.expiresAt, now: now)
            }
            if let error { Text(error).font(.caption).foregroundStyle(TodayStyle.signal) }
        }
        .padding(16)
        .background(TodayStyle.surface, in: cardShape)
        .accessibilityIdentifier("today.decision.\(item.id.rawValue)")
        .layoutProbe("today.decision.\(item.id.rawValue)")
    }

    /// Surface on Ground already separates the card; Signal stays on the deadline and the count.
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
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// A card column is wider than the Island's, so a "line" holds more characters.
    static let detailsUnitsPerLine = 96
    /// A short command with its code fence (about five lines) stays whole, copy button included.
    static let detailsPreviewLines = 6

}

struct DecisionDeadline: View {
    @Environment(\.surfaceIsVisible) private var isVisible
    let expiresAt: Date?
    let now: Date

    var body: some View {
        if let expiresAt {
            TimelineView(.periodic(from: now, by: 1).paused(!isVisible)) { context in
                Text(L("\(AttentionClock.remaining(until: expiresAt, now: context.date)) left"))
                    .font(.caption.monospacedDigit()).foregroundStyle(TodayStyle.signal)
            }
        } else {
            Text(L("No deadline")).font(.caption).foregroundStyle(TodayStyle.tertiary)
        }
    }
}
