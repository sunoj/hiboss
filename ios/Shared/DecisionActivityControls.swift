// Native reply controls shared by Live Activities and the simulator evidence fixture.
// Exports the card, response controls, and compact and minimal Island status views.
// Dependencies: SwiftUI, WidgetKit, RespondDecisionIntent and DecisionSubmissionNotice.

import SwiftUI
import WidgetKit

struct DecisionActivityControls: View {
    let messageID: String
    let state: DecisionActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if state.replyFailed != true {
                if state.options.isEmpty {
                    Link(destination: decisionActivityAppURL) {
                        Label("Reply in HiBoss", systemImage: "text.bubble")
                            .modifier(DecisionActivityButtonStyle(isPrimary: false))
                    }
                } else {
                    options
                }
                if state.options.count > 2 {
                    Link("+\(state.options.count - 2) more · Open HiBoss", destination: decisionActivityAppURL)
                        .font(.footnote.weight(.semibold))
                        .padding(.vertical, 4)
                }
            }
            DecisionSubmissionNotice(state: state)
        }
    }

    private var options: some View {
        HStack(spacing: 8) {
            ForEach(Array(state.options.prefix(2).enumerated()), id: \.offset) { index, option in
                Button(intent: RespondDecisionIntent(messageID: messageID, choice: option)) {
                    optionLabel(option)
                        .modifier(DecisionActivityButtonStyle(isPrimary: index == 0))
                }
                .buttonStyle(.plain)
            }
        }
        .disabled(state.submitting != nil || state.completion != nil)
    }

    @ViewBuilder
    private func optionLabel(_ option: String) -> some View {
        if state.submitting == option.trimmingCharacters(in: .whitespacesAndNewlines) {
            HStack(spacing: 4) {
                if state.submissionProgressVisible == true {
                    ProgressView().accessibilityHidden(true)
                }
                Text("Sending “\(option)”…")
            }
        } else {
            Text(verbatim: option)
        }
    }
}

private struct DecisionActivityButtonStyle: ViewModifier {
    var isPrimary: Bool

    func body(content: Content) -> some View {
        let ink: Color = isPrimary ? .black : .white
        content
            .font(.footnote.weight(.semibold))
            .foregroundStyle(ink)
            .tint(ink)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(.white.opacity(isPrimary ? 0.94 : 0.14), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct DecisionActivityCard: View {
    let attributes: DecisionActivityAttributes
    let state: DecisionActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let completion = state.completion {
                DecisionActivityOutcome(completion: completion, project: attributes.project)
            } else {
                header.layoutPriority(2)
                Text(verbatim: state.body).font(.headline).lineLimit(3).layoutPriority(1)
                if let content = state.content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(verbatim: content).font(.footnote).lineLimit(2).foregroundStyle(.white.opacity(0.7))
                }
                DecisionActivityControls(messageID: attributes.messageID, state: state).layoutPriority(3)
                if let option = state.defaultOption, !option.isEmpty, let deadline = state.deadline {
                    let time = DecisionActivityCountdown.time(until: deadline)
                    Text("No answer in \(time) picks “\(option)”. That is not approval.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                        .layoutPriority(2)
                }
            }
        }
        .foregroundStyle(.white)
        .tint(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            HiBossBrandIcon(size: 24)
            Text(verbatim: "\(attributes.project) · \(attributes.agentName)")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 5) {
                DecisionActivityPriority.name(state.priority)
                    .font(.footnote.weight(.bold))
                    .lineLimit(1)
                    .textCase(.uppercase)
                if let deadline = state.deadline {
                    DecisionActivityCountdown(deadline: deadline)
                }
            }
            .foregroundStyle(DecisionActivityPriority.color(state.priority))
            .layoutPriority(1)
        }
    }
}

private struct DecisionActivityOutcome: View {
    let completion: DecisionCompletion
    let project: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(iconColor).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                title.font(.subheadline.weight(.semibold)).lineLimit(3)
                if let detail {
                    Text(verbatim: detail).font(.footnote).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var title: Text {
        switch completion {
        case let .answered(option): Text("You chose “\(option)”")
        case .autoSelected: Text("Default picked · not approval")
        case .answeredElsewhere: Text("Answered elsewhere")
        }
    }

    private var detail: String? {
        switch completion {
        case .answered: project
        case let .autoSelected(option): option
        case let .answeredElsewhere(option): option
        }
    }

    private var symbol: String {
        if case .autoSelected = completion { return "clock" }
        return "checkmark"
    }

    private var iconColor: Color {
        if case .answered = completion { return .green }
        return .white.opacity(0.7)
    }
}

// Keep these system colors aligned with the app palette.
enum DecisionActivityPriority {
    static func color(_ priority: String) -> Color {
        switch priority.lowercased() {
        case "critical": .red
        case "high": .orange
        case "low": Color(.systemGray2)
        default: Color(.systemGray)
        }
    }

    static func name(_ priority: String) -> Text {
        switch priority.lowercased() {
        case "critical": Text("Critical")
        case "high": Text("High")
        case "normal": Text("Normal")
        case "low": Text("Low")
        default: Text(verbatim: priority)
        }
    }
}

private struct DecisionActivityCountdown: View {
    let deadline: Date

    var body: some View {
        Self.time(until: deadline)
            .font(.footnote.weight(.semibold).monospacedDigit())
            .multilineTextAlignment(.trailing)
            .frame(width: 52)
    }

    static func time(until deadline: Date) -> Text {
        let range = DecisionTimerRange.active(until: deadline) ?? deadline...deadline
        return Text(timerInterval: range, countsDown: true, showsHours: true)
    }
}

struct DecisionActivityCompactStatus: View {
    let state: DecisionActivityAttributes.ContentState

    var body: some View {
        let tint = DecisionActivityPriority.color(state.priority)
        if state.completion != nil {
            Image(systemName: "checkmark").foregroundStyle(.white)
        } else if let deadline = state.deadline {
            DecisionActivityCountdown(deadline: deadline).foregroundStyle(tint)
        } else {
            Text(verbatim: "?")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.black)
                .frame(width: 20, height: 20)
                .background(tint, in: Circle())
                .accessibilityLabel("Decision waiting")
        }
    }
}

struct DecisionActivityMinimalStatus: View {
    let state: DecisionActivityAttributes.ContentState

    var body: some View {
        let tint = DecisionActivityPriority.color(state.priority)
        if state.completion != nil {
            HiBossBrandIcon(size: 16)
        } else if let deadline = state.deadline {
            if let range = DecisionTimerRange.progress(from: state.askedAt, until: deadline) {
                ProgressView(timerInterval: range, countsDown: true) { EmptyView() } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.circular)
                .tint(tint)
                .frame(width: 30, height: 30)
                .accessibilityLabel("Decision waiting")
            } else {
                iconWithDot(tint)
            }
        } else {
            iconWithDot(tint)
        }
    }

    private func iconWithDot(_ tint: Color) -> some View {
        HiBossBrandIcon(size: 16)
            .padding(5)
            .overlay(alignment: .topTrailing) {
                Circle().fill(tint).frame(width: 7, height: 7)
            }
            .accessibilityLabel("Decision waiting")
    }
}
