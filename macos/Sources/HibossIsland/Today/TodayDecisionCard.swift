// Answerable decision card and native option buttons using design-v4 role colours.
// Exports: TodayDecisionCard and DecisionChoices; no ranking takes place here.
// Dependencies: SwiftUI, HibossKit AttentionItem, and TodayStyle.

import HibossKit
import SwiftUI

struct TodayDecisionCard: View {
    let item: AttentionItem
    let now: Date
    let isSelected: Bool
    let isSubmitting: Bool
    let error: String?
    let onSelect: () -> Void
    let onChoose: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(item.provenance).font(.caption).foregroundStyle(TodayStyle.secondary)
                        Spacer(minLength: 4)
                        DecisionDeadline(expiresAt: item.expiresAt, now: now)
                    }
                    Text(item.body).font(.headline).foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let content = item.content {
                        Text(content).font(.callout).foregroundStyle(TodayStyle.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityHint(L("Open decision"))
            DecisionChoices(item: item, onChoose: onChoose).disabled(isSubmitting)
            if let option = item.defaultOption {
                DecisionDefaultLine(option: option, expiresAt: item.expiresAt, now: now)
            }
            if let error { Text(error).font(.caption).foregroundStyle(TodayStyle.signal) }
        }
        .padding(16).background(TodayStyle.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(isSelected ? TodayStyle.signal : TodayStyle.hairline, lineWidth: 1))
        .accessibilityIdentifier("today.decision.\(item.id.rawValue)")
    }
}

struct DecisionChoices: View {
    let item: AttentionItem
    let onChoose: (String) -> Void

    var body: some View {
        if let media = item.message.metadata?.optionMedia, !media.isEmpty {
            OptionMediaPicker(options: item.options, media: media,
                defaultOption: item.defaultOption, choose: onChoose)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(item.options.enumerated()), id: \.offset) { index, option in
                    if index == 0 {
                        Button(option) { onChoose(option) }
                            .buttonStyle(.borderedProminent).tint(TodayStyle.ink)
                    } else {
                        Button(option) { onChoose(option) }.buttonStyle(.bordered)
                    }
                }
            }
        }
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
