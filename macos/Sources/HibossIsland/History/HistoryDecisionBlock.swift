// Native choices and settlement labels driven by the shared thread outcome.
// Exports: HistoryDecisionBlock; submission stays keyed to the parent message.
// Dependencies: SwiftUI, HibossKit, HistoryOptionGrid, and HistoryReplyActions.

import HibossKit
import SwiftUI

struct HistoryDecisionBlock: View {
    let thread: MessageThread
    let outcome: ThreadOutcome
    @ObservedObject var reply: AttentionReplyState
    let onChoose: (String) async -> ReplyFeedback?
    @State private var sendingOption: String?

    private var message: HistoryMessage { thread.message }
    private var isOpen: Bool { outcome == .open }
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
                defaultOption: message.defaultOption, outcome: outcome, isSubmitting: isSubmitting,
                sendingOption: sendingOption, choose: send)
            if !textOptions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(textOptions.enumerated()), id: \.offset) { _, option in
                        textChoice(option)
                    }
                }
            }
            settlement
            if isOpen {
                if let deadline = message.expirationDate {
                    Text(timerInterval: Date.now...max(Date.now, deadline), countsDown: true)
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                HistoryReplyActions(message: message, reply: reply, canAnswer: true, onChoose: onChoose)
            }
        }
        .accessibilityIdentifier("history.actions.\(message.id.rawValue)")
    }

    @ViewBuilder
    private func textChoice(_ option: String) -> some View {
        if isOpen {
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
            .buttonStyle(.bordered).disabled(isSubmitting)
        } else {
            let selected = HistoryOptionSelection.isSelected(option, outcome: outcome)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: HistoryOptionSelection.symbol(option, outcome: outcome))
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                Text(option).foregroundStyle(selected ? Color.primary : .secondary)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var settlement: some View {
        switch outcome {
        case .autoSelected:
            Label(L("Auto-selected when time ran out"), systemImage: "clock.arrow.circlepath")
                .font(.caption).foregroundStyle(.secondary)
        case let .chosen(_, source):
            if let source, !source.isEmpty, source.lowercased() != "macos" {
                Text(L("Answered on \(source.capitalized)"))
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
        guard isOpen, !isSubmitting, message.canAnswerHistory(at: .now) else { return }
        sendingOption = option
        Task {
            await reply.send(option, for: message.id) { text, _ in await onChoose(text) }
            sendingOption = nil
        }
    }
}
