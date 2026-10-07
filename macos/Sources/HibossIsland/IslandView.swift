// Renders the option picker for island and standard-window presentation.
// Exports: IslandView, OptionMessageBody, and OptionSurfaceStyle.
// Dependencies: SwiftUI, OptionFlowStore, and the controller-owned AttentionReplyState.

import SwiftUI
import HibossKit

enum OptionSurfaceStyle: Sendable {
    case island
    case window
}

struct IslandView: View {
    @ObservedObject var flow: OptionFlowStore
    /// Drafts, sending and feedback keyed by message id; owned outside the hosting root so a
    /// new question or presentation never erases them.
    @ObservedObject var reply: AttentionReplyState
    let surfaceStyle: OptionSurfaceStyle

    init(flow: OptionFlowStore, reply: AttentionReplyState, surfaceStyle: OptionSurfaceStyle = .island) {
        self.flow = flow
        self.reply = reply
        self.surfaceStyle = surfaceStyle
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            islandContent(now: context.date)
        }
    }

    @ViewBuilder
    private func islandContent(now: Date) -> some View {
        if case let .resolved(answer, source) = flow.presentationState, let message = flow.activeMessage {
            resolvedCard(message, answer: answer, source: source)
        } else if let presentation = IslandAttention.presentation(
            live: flow.activeMessage,
            history: flow.historyMessages,
            now: now
        ) {
            let message = presentation.message
            VStack(alignment: .leading, spacing: 0) {
                agentHeader(message, item: presentation.item, now: now)
                    .padding(.bottom, 12)
                OptionMessageBody(text: message.body)
                fixedActions(message)
            }
            .padding(.horizontal, 18)
            .padding(.top, 13)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(surfaceShape)
            .overlay(ExpiryBand(expiresAt: message.expirationDate, surfaceStyle: surfaceStyle))
        } else if surfaceStyle == .island {
            Label(L("Drop into Box"), systemImage: "tray.and.arrow.down")
                .font(.caption)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(surfaceShape)
        }
    }

    /// Shown briefly when the decision was answered on another device.
    private func resolvedCard(_ message: OptionMessage, answer: String?, source: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(projectTitle(for: message))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    messageContext(message)
                }
                Spacer()
            }
            Text(message.body)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 7) {
                ForEach(message.options, id: \.self) { option in
                    ResolvedOptionRow(title: option, chosen: option == answer, source: source)
                }
                if let answer, !message.options.contains(answer) {
                    ResolvedOptionRow(title: answer, chosen: true, source: source)
                }
            }
            if flow.replyFeedback[message.id] == .alreadyResolved {
                Text(ReplyFeedback.alreadyResolved.text)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(surfaceShape)
    }

    private func agentHeader(_ message: OptionMessage, item: AttentionItem?, now: Date) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(projectTitle(for: message))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let item, let caption = IslandAttention.autoDecisionCaption(for: item, now: now) {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                } else {
                    messageContext(message)
                }
            }
            Spacer()
            if isSubmitting(message.id) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }
            if flow.activeMessage?.id == message.id {
                SkipButton { flow.skip() }
                    .disabled(isSubmitting(message.id))
            }
        }
    }

    @ViewBuilder
    private func messageContext(_ message: OptionMessage) -> some View {
        if let content = nonEmpty(message.content) {
            Text(content)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)
        }
        if let agent = nonEmpty(message.agentName), agent != projectTitle(for: message) {
            Text(agent)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)
        }
    }

    private func projectTitle(for message: OptionMessage) -> String {
        nonEmpty(message.sessionLabel) ?? nonEmpty(message.sessionBranch) ?? nonEmpty(message.agentName) ?? productName
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// Typed text and option clicks share one path: only an accepted reply clears the draft.
    private func send(_ text: String, for messageID: MessageID) {
        Task { await reply.send(text, for: messageID, using: flow.answer) }
    }

    private func draft(for messageID: MessageID) -> Binding<String> {
        Binding(get: { reply.drafts[messageID] ?? "" }, set: { reply.drafts[messageID] = $0 })
    }

    private func optionList(_ message: OptionMessage) -> some View {
        OptionMediaPicker(
            options: message.options,
            media: message.metadata?.optionMedia ?? [],
            defaultOption: message.defaultOption,
            choose: { send($0, for: message.id) }
        )
        .disabled(isSubmitting(message.id))
    }

    private func fixedActions(_ message: OptionMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .overlay(Color.white.opacity(0.12))
            optionList(message)
            errorLabel(for: message.id)
            ReplyField(text: draft(for: message.id), isSubmitting: isSubmitting(message.id)) {
                send(reply.drafts[message.id] ?? "", for: message.id)
            }
        }
        .padding(.top, 10)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Feedback for the presented message only, never for a different live question.
    /// Mentions the saved draft only when there is one.
    @ViewBuilder
    private func errorLabel(for messageID: MessageID) -> some View {
        if let feedback = reply.errors[messageID] {
            let hasDraft = !(reply.drafts[messageID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            Text(hasDraft ? feedback.text : feedback.choiceText)
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var surfaceShape: some View {
        switch surfaceStyle {
        case .island:
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 24,
                bottomTrailingRadius: 24,
                topTrailingRadius: 0
            )
            .fill(Color.black)
        case .window:
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black)
        }
    }

    private func isSubmitting(_ messageID: MessageID) -> Bool {
        reply.submitting.contains(messageID)
    }
}

/// Renders a complete short question directly and adds scrolling only when the
/// available panel height cannot contain the question.
struct OptionMessageBody: View {
    let text: String

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView(.vertical, showsIndicators: true) { content }
        }
        .frame(minHeight: 56, maxHeight: .infinity, alignment: .top)
    }

    private var content: some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 8)
    }
}
