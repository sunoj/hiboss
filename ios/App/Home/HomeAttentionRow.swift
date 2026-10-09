// Actionable Home attention list with project, requester, wait, and choices.
// Exports: HomeAttentionSection, HomeAttentionRow, DecisionCard, and DecisionCardInfo.
// Dependencies: SwiftUI, HibossKit MessageID, AttentionItem, DecisionOptions, DecisionTiming, Theme.

import HibossKit
import SwiftUI

struct HomeAttentionSection: View {
    let snapshot: HomeAttentionSnapshot
    let hasPanels: Bool
    var isAllClear = false
    let status: String?
    var statusIsFailure = false
    var onRetry: (() async -> Void)? = nil
    var onSettings: (() -> Void)? = nil
    var replying: [MessageID: String] = [:]
    let onChoose: (String, MessageID) -> Void
    let onOpenPanel: (String) -> Void
    let onOpenSession: (SessionRoute) -> Void
    let onOpenDecision: (MessageID) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if snapshot.count > 0 { title }
            if let status {
                PendingStateView(
                    title: status, showsPlaceholder: snapshot.count == 0 && !hasPanels,
                    isFailure: statusIsFailure, statusIdentifier: "home-connection-status",
                    onRetry: onRetry, onSettings: onSettings
                )
            }
            if isAllClear {
                allClear
            } else {
                ForEach(snapshot.groups, id: \.group) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(group.items) { item in
                            HomeAttentionRow(
                                item: item, submitting: replying[item.id],
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
        .padding(.horizontal, 16)
    }

    /// Side by side at ordinary sizes; stacked at accessibility sizes, where sharing a
    /// row breaks the title across lines.
    private var title: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        return layout {
            Text("Your call")
                .fixedSize(horizontal: false, vertical: true)
                .font(.title3.bold())
                .foregroundStyle(Theme.ink)
            if !stacked { Spacer(minLength: 0) }
            if snapshot.count > 0 || (status == nil && hasPanels) {
                titleSubtitle
                    .font(.hbCaption)
                    .foregroundStyle(Theme.ink2)
            }
        }
    }

    private var titleSubtitle: Text {
        let count = snapshot.count
        guard count > 0 else {
            return status == nil
                ? Text("Nothing is waiting on your call") : Text("Checking your attention queue")
        }
        return Text("\(count) items waiting on your call")
    }

    private func questionnaireRow(_ request: PendingQuestionnaire) -> some View {
        Button { onOpenPanel(request.panelId) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: request.title).font(.hbBodyStrong).foregroundStyle(Theme.ink)
                    (request.blocking ? Text("Questionnaire · Agent waiting") : Text("Questionnaire"))
                        .font(.hbCaption).foregroundStyle(Theme.ink2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(Theme.ink3)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: 44)
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home-questionnaire-\(request.requestId)")
        .accessibilityHint("Opens the panel to answer this questionnaire")
    }

    private var allClear: some View {
        VStack(spacing: 14) {
            TodayAllClearScene()
            Text("Nothing needs you").font(.title2.bold()).foregroundStyle(Theme.ink)
            Label("Live", systemImage: "checkmark.circle.fill")
                .font(.footnote).foregroundStyle(Theme.positive)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .accessibilityElement(children: .combine)
    }

}

struct HomeAttentionRow: View {
    let item: AttentionItem
    var submitting: String?
    let onChoose: (String) -> Void
    let onOpenSession: (SessionRoute) -> Void
    let onOpenDecision: (MessageID) -> Void

    var body: some View {
        DecisionCard(message: item.message, submitting: submitting, header: infoButton,
                     choices: choices(timing: DecisionTiming(message: item.message)))
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
        if item.options.isEmpty {
            NavigationLink(value: item.id) {
                Text("Reply…").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
        } else {
            DecisionOptions(options: item.options, timing: timing, submitting: submitting,
                            wrapsToFit: true, onChoose: onChoose)
        }
    }
}

// Shared decision content keeps Today and pending thread cards in the same reading order.
struct DecisionCard<Header: View, Choices: View>: View {
    let message: HistoryMessage
    var submitting: String?
    let header: Header
    let choices: Choices
    @Environment(\.openConnectionSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let attachment = message.metadata?.attachment {
                MessageAttachmentView(attachment: attachment)
            }
            OptionMediaComparison(options: message.options, media: message.metadata?.optionMedia ?? [])
            choices
            DecisionTimingView(timing: DecisionTiming(message: message), messageID: message.id,
                               compact: true, showsNoDeadline: false)
            if submitting != nil { ReplyPendingNote(onSettings: openSettings) }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct DecisionCardInfo: View {
    let message: HistoryMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: [project, message.sessionBranch, message.displayName]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.hbCaption.weight(.semibold))
                    .foregroundStyle(Theme.ink2)
                Spacer(minLength: 8)
                if let deadline = message.expirationDate {
                    CountdownText(deadline: deadline, tint: Theme.warn).font(.footnote)
                } else {
                    Text("No deadline").font(.footnote).foregroundStyle(Theme.ink3)
                }
            }
            // The question is the reason the card exists: it wraps fully at every text size.
            Text(verbatim: message.body)
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let content = message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
               !content.isEmpty,
               content != message.body.trimmingCharacters(in: .whitespacesAndNewlines) {
                Text(verbatim: content)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
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
