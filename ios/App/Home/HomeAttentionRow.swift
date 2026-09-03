// Actionable Home attention list with project, requester, wait, and choices.
// Exports: HomeAttentionSection and HomeAttentionRow.
// Dependencies: SwiftUI, HibossKit MessageID, AttentionItem, OptionButton, Theme.

import HibossKit
import SwiftUI

struct HomeAttentionSection: View {
    let groups: [AttentionGroupItems]
    let onChoose: (String, MessageID) -> Void
    let onOpen: (MessageID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            title
            if groups.isEmpty {
                allClear
            } else {
                ForEach(groups, id: \.group) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.group.title)
                            .font(.hbCaption.weight(.semibold))
                            .foregroundStyle(group.group == .blocked ? Theme.negative : Theme.ink2)
                            .textCase(.uppercase)
                        ForEach(group.items) { item in
                            HomeAttentionRow(
                                item: item,
                                onChoose: { onChoose($0, item.id) },
                                onOpen: { onOpen(item.id) }
                            )
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Needs you now")
                .font(.hbLargeTitle)
                .foregroundStyle(Theme.ink)
            Text(verbatim: titleSubtitle)
                .font(.hbCallout)
                .foregroundStyle(Theme.ink2)
        }
    }

    private var titleSubtitle: String {
        guard !groups.isEmpty else { return "Nothing is waiting on your call" }
        let count = groups.reduce(0) { $0 + $1.items.count }
        return count == 1 ? "1 item waiting on your call" : String(count) + " items waiting on your call"
    }

    private var allClear: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.positive)
            Text("Nothing needs you")
                .font(.hbH2)
                .foregroundStyle(Theme.ink)
            Text("Everything is settled. This is where an agent's next question will appear.")
                .font(.hbCallout)
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .accessibilityElement(children: .combine)
    }
}

struct HomeAttentionRow: View {
    let item: AttentionItem
    let onChoose: (String) -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onOpen) { info }
                .buttonStyle(.plain)
            timing
            choices
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18)
                .fill(tint)
                .frame(width: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label(project, systemImage: "square.stack.3d.up")
                    .font(.hbCaption.weight(.semibold))
                    .foregroundStyle(Theme.ink2)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.hbCaption)
                    .foregroundStyle(Theme.ink4)
            }
            Text(item.message.body)
                .font(.hbBodyStrong)
                .foregroundStyle(Theme.ink)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if let content = item.message.content?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty {
                Text(content)
                    .font(.hbCaption)
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(2)
            }
            Text("Asked by \(item.message.displayName)")
                .font(.hbCaption)
                .foregroundStyle(Theme.ink3)
        }
    }

    private var project: String {
        item.project ?? String(localized: "Unassigned session")
    }

    private var tint: Color {
        switch item.group {
        case .autoDecision: return Theme.warn
        case .blocked: return Theme.negative
        case .priority: return item.message.priorityValue == .critical ? Theme.negative : Theme.warn
        }
    }

    private var timing: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Label(waitedText, systemImage: "clock")
                if item.group == .autoDecision, let deadline = item.expiresAt {
                    Spacer(minLength: 0)
                    Label { CountdownText(deadline: deadline, tint: tint) } icon: {
                        Image(systemName: "timer")
                    }
                } else if item.group == .blocked {
                    Spacer(minLength: 0)
                    Text("Agent stopped")
                }
            }
            if item.group == .autoDecision, let option = item.defaultOption {
                Label("Auto-selects \u{201C}\(option)\u{201D}", systemImage: "arrow.trianglehead.timer")
            }
        }
        .font(.hbCaption)
        .foregroundStyle(Theme.ink2)
        .accessibilityElement(children: .combine)
    }

    private var waitedText: String {
        guard let date = item.message.createdDate else { return "Waiting" }
        return "Waiting \(RelativeTime.short(from: date))"
    }

    @ViewBuilder
    private var choices: some View {
        if item.options.count == 2 {
            HStack(spacing: 6) {
                choiceButton(item.options[0])
                choiceButton(item.options[1])
            }
        } else {
            VStack(spacing: 6) {
                ForEach(item.options, id: \.self) { option in
                    choiceButton(option, alignment: .leading)
                }
            }
        }
    }

    private func choiceButton(_ option: String, alignment: Alignment = .center) -> some View {
        OptionButton(
            title: option,
            style: option == item.defaultOption ? .primary : .secondary,
            alignment: alignment,
            controlSize: .regular
        ) { onChoose(option) }
    }
}
