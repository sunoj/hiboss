// Native choices and settlement labels driven by the shared thread outcome.
// Exports: HistoryDecisionBlock; submission stays keyed to the parent message.
// Dependencies: SwiftUI, HibossKit, HistoryOptionGrid, and HistoryReplyActions.

import HibossKit
import SwiftUI

struct HistoryDecisionBlock: View {
    let thread: MessageThread
    @ObservedObject var reply: AttentionReplyState
    var answerability: AnswerableDecisions = .loading
    let onChoose: (String) async -> ReplyFeedback?
    @State private var sendingOption: String?

    private var message: HistoryMessage { thread.message }
    private var answerState: DecisionAnswerability { answerability.state(for: message.id) }
    private var displayedOutcome: ThreadOutcome { answerability.outcome(for: thread, at: .now) }
    private var isOpen: Bool { answerState == .open }
    private var isSubmitting: Bool { reply.submitting.contains(message.id) || sendingOption != nil }
    private var textOptions: [String] {
        message.options.filter { option in
            !(message.metadata?.optionMedia ?? []).contains {
                HistoryOptionSelection.matches($0.label, option)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HistoryOptionGrid(options: message.options, media: message.metadata?.optionMedia ?? [],
                defaultOption: message.defaultOption, outcome: displayedOutcome,
                isSubmitting: isSubmitting || answerState != .open,
                sendingOption: sendingOption, choose: send)
            if !textOptions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(textOptions.enumerated()), id: \.offset) { _, option in
                        textChoice(option)
                    }
                }
            }
            settlement
            if answerState == .checking {
                Button(L("Checking…")) {}.disabled(true)
            } else if answerState == .closed, displayedOutcome == .none {
                Text(ResolvedBanner.title(for: displayedOutcome, message: message) ?? L("No longer open"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if isOpen {
                HistoryDecisionTiming(option: message.defaultOption, deadline: message.expirationDate)
                HistoryReplyActions(message: message, reply: reply,
                    answerability: answerability, onChoose: onChoose)
            }
        }
        .accessibilityIdentifier("history.actions.\(message.id.rawValue)")
    }

    @ViewBuilder
    private func textChoice(_ option: String) -> some View {
        if answerState != .closed {
            Button { send(option) } label: {
                HStack(spacing: 6) {
                    Text(option).fixedSize(horizontal: false, vertical: true)
                    if HistoryOptionSelection.matches(option, message.defaultOption) {
                        Text(L("default")).foregroundStyle(.secondary)
                    }
                    if sendingOption == option { ProgressView().controlSize(.small) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered).disabled(isSubmitting || !isOpen)
        } else {
            let selected = HistoryOptionSelection.isSelected(option, outcome: displayedOutcome)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: HistoryOptionSelection.symbol(option, outcome: displayedOutcome))
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                Text(option).foregroundStyle(selected ? Color.primary : .secondary)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var settlement: some View {
        switch displayedOutcome {
        case .autoSelected:
            Label(AnswerAttribution.autoSelected, systemImage: "clock.arrow.circlepath")
                .font(.caption).foregroundStyle(.secondary)
        case let .chosen(_, source):
            if let label = thread.newestReply?.metadata?.answeredBy?.displayLabel
                ?? AnswerSource.visibleLabel(source, hiding: "macos") {
                Text(AnswerAttribution.answeredOn(label))
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .expired:
            Label(L("Expired without an answer"), systemImage: "clock")
                .font(.caption).foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    private func send(_ option: String) {
        guard answerability.permitsReply(to: message), !isSubmitting else { return }
        sendingOption = option
        Task {
            await reply.send(option, for: message.id) { text, _ in await onChoose(text) }
            sendingOption = nil
        }
    }
}

// Keep live-text ranges stable when the composer publishes a draft or submission update.
// The countdown still advances natively; draft changes must not restart its animation.
private struct HistoryDecisionTiming: View {
    let option: String?
    let deadline: Date?
    @State private var startedAt = Date()

    var body: some View {
        if let option {
            DecisionDefaultLine(option: option, expiresAt: deadline, now: startedAt)
        }
        if let deadline {
            Text(timerInterval: startedAt...max(startedAt, deadline), countsDown: true)
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}
