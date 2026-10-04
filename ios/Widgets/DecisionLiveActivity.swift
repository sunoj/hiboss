// Live Activity for a pending decision: lock-screen card + Dynamic Island.
// Exports: DecisionLiveActivity widget configuration.
// Dependencies: ActivityKit, WidgetKit, SwiftUI, shared attributes + intent.

import ActivityKit
import SwiftUI
import WidgetKit

private enum LA {
    static let ink = Color.white
    static let ink2 = Color.white.opacity(0.55)
    static let approve = Color(red: 0x5E / 255, green: 0x72 / 255, blue: 0x57 / 255)
    static let rust = Color(red: 0xE4 / 255, green: 0xA3 / 255, blue: 0x95 / 255)

    static func priorityColor(_ p: String) -> Color {
        switch p {
        case "critical": Color(red: 0xC4 / 255, green: 0x6A / 255, blue: 0x5A / 255)
        case "high": Color(red: 0xC7 / 255, green: 0x9A / 255, blue: 0x57 / 255)
        case "low": Color(red: 0x54 / 255, green: 0x53 / 255, blue: 0x4F / 255)
        default: Color(red: 0x7A / 255, green: 0x79 / 255, blue: 0x74 / 255)
        }
    }

    /// Catalog-backed priority name; an unknown value from the server shows as sent.
    static func priorityText(_ p: String) -> Text {
        switch p.lowercased() {
        case "critical": Text("Critical")
        case "high": Text("High")
        case "normal": Text("Normal")
        case "low": Text("Low")
        default: Text(verbatim: p)
        }
    }

    static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

struct DecisionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DecisionActivityAttributes.self) { context in
            LockScreenCard(context: context)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        HiBossBrandIcon(size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: context.attributes.project)
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(LA.ink)
                            if let content = LA.nonEmpty(context.state.content) {
                                Text(verbatim: content)
                                    .font(.system(size: 9)).foregroundStyle(LA.ink2)
                            } else {
                                Text(verbatim: context.attributes.meta)
                                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(LA.ink2)
                            }
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let range = DecisionTimerRange.active(until: context.state.deadline) {
                        Text(timerInterval: range, countsDown: true)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(LA.rust)
                            .frame(width: 56)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: context.attributes.agentName)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(LA.ink2)
                                .lineLimit(1)
                            Text(verbatim: context.state.body)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(LA.ink)
                                .lineLimit(2)
                        }
                        ActionButtons(context: context)
                    }
                }
            } compactLeading: {
                HiBossBrandIcon(size: 18)
            } compactTrailing: {
                if let range = DecisionTimerRange.active(until: context.state.deadline) {
                    Text(timerInterval: range, countsDown: true)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(LA.rust)
                        .frame(width: 44)
                }
            } minimal: {
                HiBossBrandIcon(size: 16)
            }
            .keylineTint(LA.priorityColor(context.state.priority))
        }
    }
}

private struct ActionButtons: View {
    let context: ActivityViewContext<DecisionActivityAttributes>

    var body: some View {
        let options = context.state.options
        let sending = context.state.submitting
        HStack(spacing: 9) {
            ForEach(Array(options.prefix(2).enumerated()), id: \.offset) { index, option in
                Button(intent: RespondDecisionIntent(messageID: context.attributes.messageID, choice: option)) {
                    Text(verbatim: option)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(index == 0 ? LA.approve : Color.white.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .opacity(sending == nil || sending == option.trimmingCharacters(in: .whitespacesAndNewlines) ? 1 : 0.4)
            }
        }
        // The shared reply gate is sending a choice from some surface: no second answer.
        .disabled(sending != nil || context.state.completion != nil)
    }
}

/// The recorded outcome: a timeout default is never worded as the boss's answer.
private struct CompletionLine: View {
    let completion: DecisionCompletion

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label { title } icon: { Image(systemName: symbol) }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isOwnAnswer ? LA.approve : LA.ink)
            if let answer {
                Text(verbatim: answer).font(.footnote).foregroundStyle(LA.ink2).lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var title: Text {
        switch completion {
        case .answered: Text("Answered")
        case .autoSelected: Text("Auto-selected when time ran out")
        case .answeredElsewhere: Text("Already answered elsewhere.")
        }
    }

    private var symbol: String {
        if case .autoSelected = completion { return "clock.arrow.circlepath" }
        return "checkmark.circle.fill"
    }

    private var isOwnAnswer: Bool {
        if case .answered = completion { return true }
        return false
    }

    private var answer: String? {
        switch completion {
        case let .answered(text), let .autoSelected(text): text
        case let .answeredElsewhere(text): text
        }
    }
}

private struct LockScreenCard: View {
    let context: ActivityViewContext<DecisionActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 11) {
                HiBossBrandIcon(size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(verbatim: context.attributes.project)
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(LA.ink)
                            .lineLimit(1)
                        LA.priorityText(context.state.priority)
                            .textCase(.uppercase)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(LA.priorityColor(context.state.priority))
                    }
                    if let content = LA.nonEmpty(context.state.content) {
                        Text(verbatim: content)
                            .font(.system(size: 11)).foregroundStyle(LA.ink2)
                            .lineLimit(1)
                    }
                    Text(verbatim: context.attributes.meta)
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(LA.ink2)
                        .lineLimit(1)
                }
                Spacer()
                if let range = DecisionTimerRange.active(until: context.state.deadline) {
                    Text(timerInterval: range, countsDown: true)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(LA.rust).frame(width: 48)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: context.attributes.agentName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(LA.ink2)
                    .lineLimit(1)
                Text(verbatim: context.state.body)
                    .font(.system(size: 14.5)).foregroundStyle(LA.ink.opacity(0.92))
                    .lineLimit(3)
            }
            if let completion = context.state.completion {
                CompletionLine(completion: completion)
            } else {
                ActionButtons(context: context)
            }
        }
        .padding(15)
    }
}
