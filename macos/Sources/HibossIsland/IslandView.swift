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
    var onOpenMain: () -> Void
    var topInset: CGFloat

    init(
        flow: OptionFlowStore, reply: AttentionReplyState,
        surfaceStyle: OptionSurfaceStyle = .island, topInset: CGFloat = 0,
        onOpenMain: @escaping () -> Void = {}
    ) {
        self.flow = flow
        self.reply = reply
        self.surfaceStyle = surfaceStyle
        self.topInset = topInset
        self.onOpenMain = onOpenMain
    }

    var body: some View {
        if flow.activeMessage == nil {
            islandContent(now: .now).environment(\.colorScheme, .dark)
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                islandContent(now: context.date).environment(\.colorScheme, .dark)
            }
        }
    }

    @ViewBuilder
    private func islandContent(now: Date) -> some View {
        if case let .resolved(answer, source) = flow.presentationState, let message = flow.activeMessage {
            resolvedCard(message, answer: answer, source: source)
        } else if let presentation = IslandAttention.presentation(
            live: flow.activeMessage,
            history: flow.historyMessages,
            now: now, withdrawn: TodayProjection.withdrawn(feedback: flow.replyFeedback)
        ) {
            let message = presentation.message
            VStack(alignment: .leading, spacing: 0) {
                agentHeader(message, item: presentation.item, now: now)
                    .padding(.bottom, 12)
                OptionMessageBody(text: message.body, attachment: message.metadata?.attachment)
                if let content = nonEmpty(message.content) {
                    Text(content).font(.callout).foregroundStyle(TodayStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                }
                if let option = message.defaultOption {
                    DecisionDefaultLine(option: option, expiresAt: message.expirationDate, now: now)
                        .padding(.top, 8)
                }
                fixedActions(message)
                queueFooter(now: now)
            }
            .padding(.horizontal, 18)
            .padding(.top, 13 + contentTopInset)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(surfaceShape)
            .overlay(ExpiryBand(expiresAt: message.expirationDate, surfaceStyle: surfaceStyle))
        } else if surfaceStyle == .island {
            Label(L("Drop into Box"), systemImage: "tray.and.arrow.down")
                .font(.caption)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, contentTopInset)
                .background(surfaceShape)
        }
    }

    /// Shown briefly when the decision was answered on another device.
    private func resolvedCard(_ message: OptionMessage, answer: String?, source: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Circle().fill(TodayStyle.settled).frame(width: 6, height: 6)
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
                .font(.headline)
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
        .padding(.top, 14 + contentTopInset)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(surfaceShape)
    }

    private func agentHeader(_ message: OptionMessage, item: AttentionItem?, now: Date) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text([projectTitle(for: message), message.sessionBranch, message.agentName]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.white).lineLimit(2)
            Spacer(minLength: 4)
            DecisionDeadline(expiresAt: message.expirationDate, now: now)
            if isSubmitting(message.id) { ProgressView().controlSize(.small) }
            if flow.activeMessage?.id == message.id {
                SkipButton { flow.skip() }.disabled(isSubmitting(message.id))
            }
        }
    }

    private func queueFooter(now: Date) -> some View {
        let count = TodayProjection.decisions(history: flow.historyMessages,
            live: flow.activeMessage, now: now,
            withdrawn: TodayProjection.withdrawn(feedback: flow.replyFeedback)).count
        return HStack {
            if count > 1 { Text(L("\(count - 1) more waiting")).font(.caption) }
            Spacer()
            Button(L("Open HiBoss"), action: onOpenMain).buttonStyle(.link)
        }.foregroundStyle(TodayStyle.tertiary).padding(.top, 10)
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
        nonEmpty(message.sessionLabel) ?? nonEmpty(message.sessionBranch)
            ?? nonEmpty(message.agentName) ?? productName
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
        Group {
            if !(message.metadata?.optionMedia.isEmpty ?? true) {
                OptionMediaPicker(options: message.options, media: message.metadata?.optionMedia ?? [],
                    defaultOption: message.defaultOption, choose: { send($0, for: message.id) })
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(Array(message.options.enumerated()), id: \.offset) { index, option in
                        if index == 0 {
                            Button(option) { send(option, for: message.id) }
                                .buttonStyle(.borderedProminent).tint(TodayStyle.ink)
                        } else {
                            Button(option) { send(option, for: message.id) }.buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
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
            let hasDraft = !(reply.drafts[messageID] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    private var contentTopInset: CGFloat {
        surfaceStyle == .island ? topInset : 0
    }

    private func isSubmitting(_ messageID: MessageID) -> Bool {
        reply.submitting.contains(messageID)
    }
}

/// Renders a complete short question directly and adds scrolling only when the
/// available panel height cannot contain the question.
struct OptionMessageBody: View {
    let text: String
    let attachment: MessageAttachment?

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView(.vertical, showsIndicators: true) { content }
        }
        .frame(minHeight: 56, alignment: .top)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let attachment {
                MessageAttachmentView(attachment: attachment)
            }
        }
        .padding(.trailing, 8)
    }
}
