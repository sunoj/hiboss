// Actionable Home attention list with project, requester, wait, and choices.
// Exports: HomeAttentionSection, HomeAttentionRow, DecisionCard, and DecisionCardInfo.
// Dependencies: SwiftUI, HibossKit MessageID, AttentionItem, DecisionOptions, DecisionTiming, Theme.

import HibossKit
import SwiftUI

struct HomeAttentionSection: View {
    let snapshot: HomeAttentionSnapshot
    let hasPanels: Bool
    var isAllClear = false
    var reservesAllClearSpace = false
    var isRefreshing = false
    let status: String?
    var statusIsFailure = false
    var onRetry: (() async -> Void)? = nil
    var onSettings: (() -> Void)? = nil
    var replying: [MessageID: String] = [:]
    var verifying: Set<MessageID> = []
    var verificationTimedOut: Set<MessageID> = []
    var answerability: [MessageID: DecisionAnswerability] = [:]
    var inputsLoaded = true
    let onChoose: (String, MessageID) -> Void
    let onOpenPanel: (String) -> Void
    let onOpenSession: (SessionRoute) -> Void
    let onOpenDecision: (MessageID) -> Void
    @State private var refreshVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if snapshot.count > 0 { title }
            if isAllClear {
                allClear
            } else if reservesAllClearSpace && snapshot.count == 0 {
                allClear.hidden().accessibilityHidden(true)
            } else {
                ForEach(snapshot.groups, id: \.group) { group in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        ForEach(group.items) { item in
                            HomeAttentionRow(
                                item: item, submitting: replying[item.id],
                                locksControls: !verifying.contains(item.id)
                                    || verificationTimedOut.contains(item.id),
                                verifying: verifying.contains(item.id),
                                verificationTimedOut: verificationTimedOut.contains(item.id),
                                answerability: answerability[item.id] ?? .checking,
                                onChoose: { onChoose($0, item.id) }, onOpenSession: onOpenSession,
                                onOpenDecision: onOpenDecision
                            )
                        }
                    }
                }
                ForEach(snapshot.questionnaires) { request in
                    questionnaireRow(request)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.m)
        .task(id: isRefreshing) {
            refreshVisible = false
            guard isRefreshing else { return }
            do { try await Task.sleep(for: PendingTiming.revealDelay) }
            catch { return }
            refreshVisible = true
        }
    }

    private var title: some View {
        Text("Your call").hbSectionHeader()
            .padding(.horizontal, Space.m)
    }

    private func questionnaireRow(_ request: PendingQuestionnaire) -> some View {
        Button { onOpenPanel(request.panelId) } label: {
            HStack(spacing: Space.s) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(verbatim: request.title).font(.hbBodyStrong).foregroundStyle(Theme.ink)
                    (request.blocking ? Text("Questionnaire · Agent waiting") : Text("Questionnaire"))
                        .font(.hbCaption).foregroundStyle(Theme.ink2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(Theme.ink3)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: ControlMetric.minTap)
            .padding(Space.s)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.large))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home-questionnaire-\(request.requestId)")
        .accessibilityHint("Opens the panel to answer this questionnaire")
    }

    private var allClear: some View {
        HStack(spacing: Space.s) {
            idleIllustration
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Nothing needs you").font(.headline).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                ZStack(alignment: .leading) {
                    Label("Checking coverage", systemImage: "exclamationmark.circle").hidden()
                    Label("Refreshing…", systemImage: "arrow.triangle.2.circlepath").hidden()
                    if statusIsFailure {
                        Label("Checking coverage", systemImage: "exclamationmark.circle")
                            .foregroundStyle(Theme.warn)
                    } else if refreshVisible {
                        Label("Refreshing…", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundStyle(Theme.live)
                    } else {
                        Label("Live", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.positive)
                    }
                }.font(.footnote).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today-all-clear")
    }

    private var idleIllustration: some View {
        TodayIdleIllustration(ink: Theme.ink2, accent: Theme.positive)
    }

}

struct HomeAttentionRow: View {
    let item: AttentionItem
    var submitting: String?
    var locksControls = true
    var verifying = false
    var verificationTimedOut = false
    var answerability: DecisionAnswerability = .checking
    let onChoose: (String) -> Void
    let onOpenSession: (SessionRoute) -> Void
    let onOpenDecision: (MessageID) -> Void

    var body: some View {
        DecisionCard(message: item.message, submitting: submitting, verifying: verifying,
                     verificationTimedOut: verificationTimedOut, header: header,
                     choices: choices(timing: DecisionTiming(message: item.message)))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            infoButton
            MessageReactions(message: item.message)
            if let content = item.message.messageText.content,
               !content.isEmpty,
               content != item.message.body.trimmingCharacters(in: .whitespacesAndNewlines) {
                MediaMarkdownView(content).font(.subheadline).foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var infoButton: some View {
        Button { onOpenDecision(item.id) } label: { DecisionCardInfo(message: item.message) }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home-message-\(item.id.rawValue)")
            .contextMenu {
                if let sessionRoute {
                    Button("View session", systemImage: "text.alignleft") { onOpenSession(sessionRoute) }
                        .accessibilityIdentifier("home-session-\(item.id.rawValue)")
                }
            }
            .accessibilityActions {
                if let sessionRoute {
                    Button("View session") { onOpenSession(sessionRoute) }
                }
            }
    }

    private var sessionRoute: SessionRoute? {
        guard let id = item.message.sessionId,
              !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return SessionRoute(message: item.message)
    }

    @ViewBuilder
    private func choices(timing: DecisionTiming) -> some View {
        if let label = answerability.label {
            Button {} label: {
                Text(verbatim: label).frame(maxWidth: .infinity, minHeight: ControlMetric.minTap)
            }
                .hbButton(.secondary).disabled(true)
        } else if item.options.isEmpty {
            NavigationLink(value: item.id) {
                Text("Reply…").frame(maxWidth: .infinity, minHeight: ControlMetric.minTap)
            }
            .hbButton(.secondary)
        } else {
            DecisionOptions(options: item.options, metadata: item.message.metadata,
                            timing: timing, submitting: submitting,
                            locksControls: locksControls,
                            wrapsToFit: true, onChoose: onChoose)
        }
    }
}

// Shared decision content keeps Today and pending thread cards in the same reading order.
struct DecisionCard<Header: View, Choices: View>: View {
    let message: HistoryMessage
    var submitting: String?
    var verifying = false
    var verificationTimedOut = false
    let header: Header
    let choices: Choices
    @Environment(\.openConnectionSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            header
            if let attachment = message.metadata?.attachment {
                MessageAttachmentView(attachment: attachment)
            }
            OptionMediaComparison(options: message.options, media: message.metadata?.optionMedia ?? [],
                                  metadata: message.metadata)
            choices
            DecisionTimingView(timing: DecisionTiming(message: message), messageID: message.id,
                               compact: true, showsNoDeadline: false)
            if verificationTimedOut {
                Text("This is taking longer than expected.").font(.footnote).foregroundStyle(Theme.ink2)
            } else if submitting != nil && !verifying {
                ReplyPendingNote(onSettings: openSettings)
            }
        }
        .hbCard()
    }
}

struct DecisionCardInfo: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.projectSessions) private var inventory
    let message: HistoryMessage

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .center, spacing: Space.xs) {
                ProjectAvatarView(project: inventory.first { $0.id == message.sessionId }?.avatarProject
                                  ?? inventory.project(slug: message.project ?? project),
                                  size: AvatarSize.compact)
                metadata
                    .font(.hbCaption.weight(.semibold))
                    .foregroundStyle(Theme.ink2)
                Spacer(minLength: Space.xs)
                if let deadline = message.expirationDate {
                    CountdownText(deadline: deadline, tint: Theme.warn).font(.footnote)
                        .lineLimit(1).fixedSize()
                } else {
                    Text("No deadline").font(.footnote).foregroundStyle(Theme.ink3)
                        .lineLimit(1).fixedSize()
                }
            }
            // The question is the reason the card exists: it wraps fully at every text size.
            Text(verbatim: message.messageText.title)
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: ControlMetric.minTap, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var metadata: some View {
        let layout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(spacing: Space.xxs))
        return layout {
            Text(verbatim: inventory.first { $0.id == message.sessionId }?.namedLabel ?? project)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            Text(verbatim: (textSize.isAccessibilitySize ? "" : "· ")
                 + [message.sessionBranch, message.displayName].compactMap { $0 }.joined(separator: " · "))
                .lineLimit(1).truncationMode(.tail)
        }
    }

    private var project: String {
        [message.sessionLabel, message.sessionBranch].compactMap { value -> String? in
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                return nil
            }
            return value
        }.first ?? String(localized: "Unassigned session")
    }
}
