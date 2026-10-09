// Actionable Home attention list with project, requester, wait, and choices.
// Exports: HomeAttentionSection and HomeAttentionRow.
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
                                onChoose: { onChoose($0, item.id) }, onOpenSession: onOpenSession
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
    @Environment(\.openConnectionSettings) private var openSettings

    var body: some View {
        let timing = DecisionTiming(message: item.message)
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: item.id) { info }
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
            if let attachment = item.message.metadata?.attachment {
                MessageAttachmentView(attachment: attachment)
            }
            OptionMediaComparison(
                options: item.options,
                media: item.message.metadata?.optionMedia ?? []
            )
            choices(timing: timing)
            DecisionTimingView(timing: timing, messageID: item.id, compact: true)
            if submitting != nil { ReplyPendingNote(onSettings: openSettings) }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: [project, item.message.sessionBranch, item.message.displayName]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.hbCaption.weight(.semibold))
                    .foregroundStyle(Theme.ink2)
                Spacer(minLength: 8)
                if let deadline = item.expiresAt {
                    CountdownText(deadline: deadline, tint: Theme.warn).font(.footnote)
                } else {
                    Text("No deadline").font(.footnote).foregroundStyle(Theme.ink3)
                }
            }
            // The question is the reason the card exists: it wraps fully at every text size.
            Text(verbatim: item.message.body)
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let content = item.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
               !content.isEmpty,
               content != item.message.body.trimmingCharacters(in: .whitespacesAndNewlines) {
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
        item.project ?? String(localized: "Unassigned session")
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
