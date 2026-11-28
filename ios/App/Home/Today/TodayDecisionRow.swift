// One-line Today row for an open decision after the focus card; it opens the decision sheet.
// Exports: TodayDecisionRows (the grouped list) and TodayDecisionRow.
// Dependencies: SwiftUI, HibossKit AttentionItem, ProjectAvatarView, CountdownText, Theme.

import HibossKit
import SwiftUI

/// The decisions after the focus card, in the snapshot's order, as one grouped list.
struct TodayDecisionRows: View {
    let items: [AttentionItem]
    let onOpenDecision: (MessageID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider().padding(.leading, Space.m) }
                TodayDecisionRow(item: item, onOpen: { onOpenDecision(item.id) })
            }
        }
        .background(Theme.surface, in: shape)
        .clipShape(shape)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
    }
}

struct TodayDecisionRow: View {
    @Environment(\.projectSessions) private var inventory
    @Environment(\.selectedDecision) private var selectedDecision
    @Environment(\.dynamicTypeSize) private var textSize
    let item: AttentionItem
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: Space.s) {
                ProjectAvatarView(project: project, size: AvatarSize.compact).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(verbatim: item.message.messageText.title)
                        .font(.hbSmall.weight(.semibold)).foregroundStyle(Theme.ink)
                        // One line, except at accessibility sizes, where a cut-off question says nothing.
                        .lineLimit(textSize.isAccessibilitySize ? nil : 1)
                        .fixedSize(horizontal: false, vertical: textSize.isAccessibilitySize)
                    Text(verbatim: meta).font(.hbFootnote).foregroundStyle(Theme.ink3).lineLimit(1)
                }
                .layoutPriority(1)
                Spacer(minLength: Space.xs)
                deadline
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Theme.ink3)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: ControlMetric.minTap, alignment: .leading)
            .padding(.horizontal, Space.s).padding(.vertical, Space.xs)
            .background(isSelected ? Theme.surface2 : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home-message-\(item.id.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var isSelected: Bool { selectedDecision == item.id }

    @ViewBuilder private var deadline: some View {
        if let deadline = item.expiresAt {
            CountdownText(deadline: deadline, tint: Theme.warn, bare: true).font(.footnote.weight(.semibold))
                .lineLimit(1).fixedSize()
        } else {
            Text("No deadline").font(.footnote).foregroundStyle(Theme.ink3).lineLimit(1).fixedSize()
        }
    }

    private var project: ProjectIdentity {
        inventory.first { $0.id == item.message.sessionId }?.avatarProject
            ?? inventory.project(slug: item.message.project ?? item.project ?? "")
    }

    /// "project · branch · what answering takes", most specific first.
    private var meta: String {
        let session = inventory.first { $0.id == item.message.sessionId }?.namedLabel ?? item.project
        let branch = item.message.sessionBranch.flatMap { $0 == session ? nil : $0 }
        return [session, branch, kind].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: " · ")
    }

    private var kind: String {
        if item.message.metadata?.form != nil { return String(localized: "Form") }
        if item.options.isEmpty { return String(localized: "Reply") }
        if !(item.message.metadata?.optionMedia ?? []).isEmpty {
            return String(localized: "\(item.options.count) choices with pictures")
        }
        return String(localized: "\(item.options.count) choices")
    }
}
