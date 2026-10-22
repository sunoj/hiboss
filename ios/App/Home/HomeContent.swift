// Home content: the attention surface, the only Home view that observes the stores.
// Exports: HomeContent; its store-driven redraws stay below the shell's refresh action.
// Dependencies: SwiftUI, InboxStore, AttentionModel, HomeAttentionSection, and PanelsModel.

import HibossKit
import SwiftUI

struct HomeContent: View {
    @ObservedObject var inbox: InboxStore
    @ObservedObject var panels: PanelsModel
    @Binding var actionNote: String?
    @Binding var decisionID: MessageID?
    @Binding var showingDecision: Bool
    @Binding var sessionRoute: SessionRoute?
    @Environment(\.openConnectionSettings) private var openSettings
    @State private var hasCompletedCoverage = false

    var body: some View {
        content
            .onChange(of: attentionStatus == nil, initial: true) { _, complete in
                if complete {
                    hasCompletedCoverage = true
                    StartupLog.record("Today settled")
                }
            }
            .onChange(of: inbox.didLoad) { _, loaded in
                if !loaded { hasCompletedCoverage = false }
            }
            .sheet(isPresented: Binding(
                get: { panels.selectedTile != nil },
                set: { if !$0 { panels.closeDetail() } }
            )) {
                if let tile = panels.selectedTile { HomePanelDetail(tile: tile, model: panels) }
            }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 22) {
                TimelineView(HomeRefreshSchedule(deadlines: refreshDeadlines)) { context in
                    todayContent(now: context.date)
                }
            }
            .padding(.vertical, 12)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CompactRefreshNotice(isRefreshing: isRefreshingKnownContent,
                                 error: hasCompletedCoverage && hasCoverageFailure && !connectionLost
                                     ? attentionStatus : nil,
                                 title: attentionStatus ?? String(localized: "Refreshing…"),
                                 onRetry: { await retryCoverage() },
                                 statusIdentifier: "home-connection-status", revealsWhenSlow: true)
        }
    }

    /// Expiry moments that change the ranking; countdown text ticks on its own.
    private var refreshDeadlines: [Date] {
        (inbox.history + inbox.requiredInputs).compactMap(\.expirationDate)
            + panels.pendingQuestionnaires.compactMap { $0.expiresAt.flatMap(ISODate.parse) }
    }

    private func todayContent(now: Date) -> some View {
        let refreshing = isRefreshingKnownContent
        let today = inbox.todaySnapshot(now: now, coverageComplete: attentionStatus == nil)
        let attention = HomeAttentionSnapshot(
            messages: [], withdrawn: inbox.withdrawn, questionnaires: panels.pendingQuestionnaires,
            decisions: today.decisions,
            terminalPanelIDs: Set(panels.tiles.filter { $0.lifecycle.taskState.isTerminal }.map(\.id)),
            now: now, panelNow: { panels.serverNow(for: $0) }
        )
        let onRetry: (() async -> Void)? = inbox.isReady ? { await retryCoverage() } : nil
        let isAllClear = (today.isAllClear || (hasCompletedCoverage && today.decisions.isEmpty))
            && attention.questionnaires.isEmpty && !connectionLost
        return VStack(spacing: 22) {
            TodayHeader(snapshot: today, requestCount: attention.count,
                        inputsLoaded: inbox.requiredInputLoaded || !inbox.isReady, isRefreshing: refreshing,
                        now: now, onSettings: openSettings)
            // An empty section under a failure would still take two stack gaps from the results.
            if attention.count > 0 || isAllClear || !blocksCoverage {
                HomeAttentionSection(
                    snapshot: attention, hasPanels: !panels.visibleTiles.isEmpty,
                    isAllClear: isAllClear,
                    reservesAllClearSpace: attention.count == 0 && !blocksCoverage,
                    isRefreshing: refreshing, status: refreshing ? nil : attentionStatus,
                    statusIsFailure: hasCoverageFailure,
                    onRetry: onRetry, onSettings: openSettings,
                    replying: inbox.replying,
                    verifying: inbox.replyGate.verifying,
                    verificationTimedOut: inbox.replyGate.verificationTimedOut,
                    answerability: Dictionary(uniqueKeysWithValues: today.decisions.map {
                        ($0.id, inbox.answerability(for: $0.id, now: now))
                    }), inputsLoaded: inbox.requiredInputLoaded, onChoose: handleReply,
                    onOpenPanel: openPanel, onOpenSession: { sessionRoute = $0 },
                    onOpenDecision: {
                        decisionID = $0
                        showingDecision = true
                    }
                )
            }
            // A failure owns the space under the header: recovery must not sit below the results.
            if blocksCoverage { coverageStatus(placeholder: false) }
            TodayResults(snapshot: today)
            if !panels.tiles.isEmpty { HomePanelWall(model: panels) }
            if !blocksCoverage {
                coverageStatus(placeholder: attention.count == 0 && panels.tiles.isEmpty
                    && today.working.isEmpty && today.delivered.isEmpty)
            }
        }
    }

    /// Coverage wait or failure before the first complete check, or a lost connection at any
    /// time. Retry needs a started connection; without one only Settings can recover.
    @ViewBuilder private func coverageStatus(placeholder: Bool) -> some View {
        if !hasCompletedCoverage || connectionLost, let attentionStatus {
            PendingStateView(title: attentionStatus, showsPlaceholder: placeholder,
                             isFailure: blocksCoverage,
                             statusIdentifier: "home-connection-status",
                             onRetry: inbox.isReady ? { await retryCoverage() } : nil,
                             onSettings: openSettings)
                .padding(.horizontal, 16)
        }
    }

    /// Nothing more will load until the boss acts: not connected, or a check failed.
    private var blocksCoverage: Bool { !inbox.isReady || hasCoverageFailure }

    /// A dead connection cannot vouch for an earlier check, which a reconnect attempt may
    /// have marked complete during its brief connected state.
    private var connectionLost: Bool {
        !inbox.isReady || HomeConnectionStatus.isFailure(inbox.connectionState)
    }

    private var isRefreshingKnownContent: Bool {
        hasCompletedCoverage && (inbox.isRefreshing || inbox.requiredInputRefreshing
            || panels.isRefreshing || (!hasCoverageFailure && attentionStatus != nil))
    }

    var attentionStatus: String? {
        if !inbox.isReady { return String(localized: "Not connected") }
        if let connectionNotice = HomeConnectionStatus.notice(for: inbox.connectionState) {
            return connectionNotice
        }
        if let error = inbox.requiredInputError ?? inbox.loadError
            ?? panels.questionnaireError ?? panels.failureMessage {
            if !inbox.requiredInputs.isEmpty || !panels.visibleTiles.isEmpty {
                let failure = String(
                    localized: "Couldn't check all requests. Showing earlier results. \(error)")
                return namedFailure(failure)
            }
            return namedFailure(String(localized: "Couldn't check all requests. \(error)"))
        }
        let sources = outstandingSources
        guard !sources.isEmpty else { return nil }
        return String(localized: "Waiting for: \(sources.formatted(.list(type: .and))).")
    }

    private func namedFailure(_ failure: String) -> String {
        let sources = outstandingSources.formatted(.list(type: .and))
        let waiting = String(localized: "Waiting for: \(sources).")
        return waiting + " " + failure
    }

    private var outstandingSources: [String] {
        var sources: [String] = []
        if !inbox.requiredInputReady { sources.append(String(localized: "Requests connection")) }
        else if !inbox.hasCompleteRequiredInputs { sources.append(String(localized: "Requests")) }
        if !inbox.didLoad || inbox.isRefreshing || inbox.loadError != nil {
            sources.append(String(localized: "Messages"))
        }
        if panels.loadState != .loaded || panels.isRefreshing
            || panels.tiles.contains(where: { !panels.hasPanelCoverage(for: $0) }) {
            sources.append(String(localized: "Panels"))
        }
        if !panels.hasCompleteQuestionnaires || panels.questionnaireError != nil {
            sources.append(String(localized: "Questionnaires"))
        }
        return sources
    }

    private var hasCoverageFailure: Bool {
        inbox.requiredInputError != nil || inbox.loadError != nil
            || panels.questionnaireError != nil || panels.failureMessage != nil
            || HomeConnectionStatus.isFailure(inbox.connectionState)
    }

    private func retryCoverage() async {
        if inbox.connectionState != .connected { inbox.retryConnection() }
        else { inbox.retryRequiredInputConnection() }
        async let messages: Void = inbox.refresh()
        async let wall: Void = panels.retryLoading()
        _ = await (messages, wall)
    }

    private func openPanel(_ id: String) {
        guard panels.tiles.contains(where: { $0.id == id }) else {
            actionNote = String(localized: "This panel isn't available yet. Pull to refresh and try again.")
            return
        }
        panels.open(id)
    }

    private func handleReply(_ choice: String, to id: MessageID) {
        Task {
            if let note = await inbox.replyWithFeedback(choice, to: id) { actionNote = note }
        }
    }
}
