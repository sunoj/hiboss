// Renders the option picker for island and standard-window presentation.
// Exports: IslandView, OptionMessageBody, and OptionSurfaceStyle.
// Dependencies: SwiftUI and OptionFlowStore observation.

import SwiftUI
import HibossKit

enum OptionSurfaceStyle: Sendable {
    case island
    case window
}

struct IslandView: View {
    @ObservedObject var flow: OptionFlowStore
    let surfaceStyle: OptionSurfaceStyle
    @State private var replyText = ""

    init(flow: OptionFlowStore, surfaceStyle: OptionSurfaceStyle = .island) {
        self.flow = flow
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
            .onChange(of: message.id) { replyText = "" }
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
            if case .submitting = flow.presentationState {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }
            if flow.activeMessage?.id == message.id {
                SkipButton { flow.skip() }
                    .disabled(isSubmitting)
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
        nonEmpty(message.sessionLabel) ?? nonEmpty(message.sessionBranch) ?? nonEmpty(message.agentName) ?? "HiBoss"
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func submitReply(for messageID: MessageID) {
        let pending = replyText
        Task {
            let trimmed = pending.trimmingCharacters(in: .whitespacesAndNewlines)
            let sent: Bool
            if flow.activeMessage?.id == messageID {
                sent = await flow.submit(pending, for: messageID)
            } else if trimmed.isEmpty {
                sent = false
            } else {
                sent = await flow.answerHistory(trimmed, for: messageID)
            }
            if sent { replyText = "" }
        }
    }

    private func optionList(_ message: OptionMessage) -> some View {
        VStack(spacing: 7) {
            ForEach(message.options, id: \.self) { option in
                OptionButton(title: option, isDefault: option == message.defaultOption) {
                    chooseOption(option, for: message.id)
                }
                .disabled(isSubmitting)
            }
        }
    }

    private func fixedActions(_ message: OptionMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .overlay(Color.white.opacity(0.12))
            optionList(message)
            errorLabel
            ReplyField(text: $replyText, isSubmitting: isSubmitting) {
                submitReply(for: message.id)
            }
        }
        .padding(.top, 10)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func chooseOption(_ option: String, for messageID: MessageID) {
        Task {
            if flow.activeMessage?.id == messageID {
                await flow.choose(option, for: messageID)
            } else {
                await flow.answerHistory(option, for: messageID)
            }
        }
    }

    @ViewBuilder
    private var errorLabel: some View {
        if case let .failed(message) = flow.presentationState {
            Text(message)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.red.opacity(0.9))
                .lineLimit(1)
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

    private var isSubmitting: Bool {
        if case .submitting = flow.presentationState { return true }
        return false
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
