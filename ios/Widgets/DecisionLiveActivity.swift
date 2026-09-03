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
                        Logo()
                        VStack(alignment: .leading, spacing: 1) {
                            Text(context.attributes.project)
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(LA.ink)
                            if let content = LA.nonEmpty(context.state.content) {
                                Text(content)
                                    .font(.system(size: 9)).foregroundStyle(LA.ink2)
                            } else {
                                Text(context.attributes.meta)
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
                            Text(context.attributes.agentName)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(LA.ink2)
                                .lineLimit(1)
                            Text(context.state.body)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(LA.ink)
                                .lineLimit(2)
                        }
                        ActionButtons(context: context)
                    }
                }
            } compactLeading: {
                Logo(size: 18)
            } compactTrailing: {
                if let range = DecisionTimerRange.active(until: context.state.deadline) {
                    Text(timerInterval: range, countsDown: true)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(LA.rust)
                        .frame(width: 44)
                }
            } minimal: {
                Logo(size: 16)
            }
            .keylineTint(LA.priorityColor(context.state.priority))
        }
    }
}

private struct Logo: View {
    var size: CGFloat = 30
    var body: some View {
        Text("h")
            .font(.system(size: size * 0.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [Color(white: 0.23), Color(white: 0.09)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

private struct ActionButtons: View {
    let context: ActivityViewContext<DecisionActivityAttributes>

    var body: some View {
        let options = context.state.options
        HStack(spacing: 9) {
            ForEach(Array(options.prefix(2).enumerated()), id: \.offset) { index, option in
                Button(intent: RespondDecisionIntent(messageID: context.attributes.messageID, choice: option)) {
                    Text(option)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(index == 0 ? LA.approve : Color.white.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct LockScreenCard: View {
    let context: ActivityViewContext<DecisionActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 11) {
                Logo(size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(context.attributes.project)
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(LA.ink)
                            .lineLimit(1)
                        Text(context.state.priority.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(LA.priorityColor(context.state.priority))
                    }
                    if let content = LA.nonEmpty(context.state.content) {
                        Text(content)
                            .font(.system(size: 11)).foregroundStyle(LA.ink2)
                            .lineLimit(1)
                    }
                    Text(context.attributes.meta)
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
                Text(context.attributes.agentName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(LA.ink2)
                    .lineLimit(1)
                Text(context.state.body)
                    .font(.system(size: 14.5)).foregroundStyle(LA.ink.opacity(0.92))
                    .lineLimit(3)
            }
            if !context.state.resolved {
                ActionButtons(context: context)
            } else {
                Text("Answered")
                    .font(.system(size: 13, design: .monospaced)).foregroundStyle(LA.approve)
            }
        }
        .padding(15)
    }
}
