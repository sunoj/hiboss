// One-line Today decision: who asks, what, and how long is left; Answer expands it in place.
// Exports: TodayDecisionRow and TodayDecisionFocus (which decision is the full card).
// Dependencies: SwiftUI, HibossKit AttentionItem, DecisionDeadline, and TodayStyle.

import HibossKit
import SwiftUI

/// Which decision shows as the full card. Order is never changed: the selected decision
/// expands where it stands, and without a selection the first decision is the focus.
enum TodayDecisionFocus {
    static func focusID(_ decisions: [AttentionItem], selection: MessageID?) -> MessageID? {
        if let selection, decisions.contains(where: { $0.id == selection }) { return selection }
        return decisions.first?.id
    }
}

struct TodayDecisionRow: View {
    @Environment(\.projectSessions) private var inventory
    let item: AttentionItem
    let now: Date
    let onAnswer: () -> Void

    var body: some View {
        let project = item.project(in: inventory)
        HStack(spacing: 12) {
            ProjectAvatarView(project: project, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.message.messageText.title)
                    .font(.callout.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                Text(verbatim: item.provenance(project: project.displayName))
                    .font(.caption).foregroundStyle(TodayStyle.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            DecisionDeadline(expiresAt: item.expiresAt, now: now)
            Button(L("Answer"), action: onAnswer)
                .controlSize(.small)
                .accessibilityIdentifier("today.decision.answer")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(TodayStyle.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onAnswer)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("today.decision.\(item.id.rawValue)")
        .layoutProbe("today.decision.\(item.id.rawValue)")
    }
}
