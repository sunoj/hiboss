// Session transcript: live events or cached history, with scroll lock and in-place decisions.
// Exports: SessionMessagesView bound to SessionStreamStore, InboxStore and SessionRoute.
// Dependencies: SwiftUI, UIKit haptics, HibossKit SessionStreamStore, system semantic styles.

import HibossKit
import SwiftUI
import UIKit

struct SessionMessagesView: View {
    let route: SessionRoute
    let api: (any SessionStreamServing)?
    @ObservedObject var store: InboxStore

    let panels: PanelsModel?
    @StateObject private var facts = SessionFactsStore()
    @StateObject private var stream: SessionStreamStore
    @Environment(\.scenePhase) private var scenePhase
    private var hasLoaded: Bool { stream.didLoad || stream.usesHistory }
    @State private var actionNote: String?
    @State private var showsHistory = false
    @State private var jumpToLatestRequest = 0

    init(route: SessionRoute, api: (any SessionStreamServing)?, store: InboxStore,
         panels: PanelsModel? = nil) {
        self.panels = panels
        self.route = route
        self.api = api
        self.store = store
        _stream = StateObject(wrappedValue: SessionStreamStore(sessionID: route.id))
    }

    private var connectedTranscript: some View {
        ZStack(alignment: .bottom) {
            content
            if !stream.isFollowingLive, !stream.usesHistory {
                jumpToLiveButton
            }
        }
        .background(Theme.paper)
        .safeAreaInset(edge: .bottom) {
            SessionReplyComposer(targets: SessionReplyTarget.eligible(events: transcriptEvents, store: store),
                                 store: store)
        }
        .navigationTitle(Text(verbatim: facts.session?.namedLabel ?? route.label))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(showsHistory ? .visible : .hidden, for: .tabBar)
        .toolbar { historyToolbar }
        .navigationDestination(isPresented: $showsHistory) {
            MessagesView(store: store, sessionID: route.id).navigationTitle("Messages")
                .toolbar(.visible, for: .tabBar)
        }
    }

    private var observedTranscript: some View {
        connectedTranscript
        .task(id: route.id) {
            if let api { stream.start(api: api) }
            if route.id != SessionGrouping.directSessionID {
                await facts.load(id: route.id, api: store.api as? any SessionsServing)
            }
        }
        .onDisappear { stream.stop() }
        .onChange(of: store.replyConfirmation) { _, confirmation in
            if confirmation != nil { Task { await stream.refresh() } }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { stream.resumeFromForeground() }
        }
        .refreshable { await refresh() }
    }

    private func refresh() async {
        await stream.refresh()
        if route.id != SessionGrouping.directSessionID {
            await facts.load(id: route.id, api: store.api as? any SessionsServing)
        }
        if let panels { await panels.load() }
    }

    private var historyToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack {
                Button { Task { await refresh() } } label: {
                    Image(systemName: "arrow.clockwise").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Refresh")
                .accessibilityIdentifier("session-refresh")
                Button {
                    showsHistory = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }.accessibilityLabel("Message history")
                if !stream.usesHistory { ConnectionDot(state: stream.connectionState) }
            }
        }
    }

    var body: some View {
        observedTranscript
        .modifier(SessionReadTracking(inbox: store, sessionID: route.id, events: transcriptEvents))
        .alert(
            String(localized: "Transcript reloaded"),
            isPresented: Binding(
                get: { stream.needsResyncNotice },
                set: { if !$0 { stream.dismissResyncNotice() } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) { stream.dismissResyncNotice() }
        } message: {
            Text(String(localized: "History was truncated on the server, so the transcript was reloaded."))
        }
        .alert(
            "Heads up",
            isPresented: Binding(get: { actionNote != nil }, set: { if !$0 { actionNote = nil } }),
            presenting: actionNote
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { note in
            Text(verbatim: note)
        }
    }

    private var content: some View {
        ListStateView(
            isLoading: !stream.usesHistory && (!hasLoaded || stream.isLoading), error: stream.loadError,
            isEmpty: transcriptEvents.isEmpty && !stream.usesHistory,
            emptyIcon: "text.alignleft", emptyTitle: String(localized: "No events yet"),
            emptyDetail: String(localized: "This session has no transcript events yet."),
            loadingTitle: String(localized: "Loading transcript…"),
            hasLoaded: hasLoaded,
            reconnecting: !stream.usesHistory && stream.connectionState != .connected,
            onRetry: { await stream.refresh() }
        ) { transcript }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    transcriptContext
                    if stream.hasEarlier {
                        earlierEvents
                    }
                    SessionConversation(messages: SessionThreadMessages.messages(
                        sessionID: route.id, history: store.history, events: transcriptEvents),
                        store: store, sessionAgent: sessionAgent, onChoose: handleReply)
                        .id("conversation-start")
                    ForEach(SessionTranscriptLayout.items(from: transcriptEvents.filter {
                        $0.kind != "message"
                    })) { item in
                        SessionTranscriptItemView(item: item, store: store, sessionAgent: sessionAgent,
                                                  onChoose: handleReply)
                            .id(item.id)
                    }
                    if let panels { SessionPanelCards(sessionID: route.id, model: panels) }
                    if stream.usesHistory {
                        Text(verbatim: historyNote).font(.footnote).foregroundStyle(Theme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                            .accessibilityIdentifier("session-history-note")
                        if route.id != SessionGrouping.directSessionID {
                            RetryButton { await stream.refresh() }
                        }
                    }
                    Color.clear.frame(height: 1).id("live-end")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .accessibilityIdentifier("session-transcript")
            .coordinateSpace(name: "transcript")
            .simultaneousGesture(readerGesture)
            .onChange(of: jumpToLatestRequest) { _, _ in
                scrollToLive(proxy)
            }
        }
    }

    private var readerGesture: some Gesture {
        DragGesture(minimumDistance: 8).onChanged { value in
            if value.translation.height > 12 { stream.readerScrolledAway() }
        }
    }

    @ViewBuilder private var transcriptContext: some View {
        if let error = facts.error {
            Text(verbatim: error).font(.footnote).foregroundStyle(Theme.ink2)
            RetryButton { await facts.load(id: route.id, api: store.api as? any SessionsServing) }
        }
        if let current = facts.session, !stream.usesHistory {
            SessionFactsHeader(session: current)
            TimelineView(.periodic(from: .now, by: 60)) { context in
                ProjectPeersView(peers: RecentProjectPeers.all(
                    current: current, sessions: facts.sessions, messages: store.history,
                    now: context.date))
            }
        }
    }

    private var historyNote: String {
        route.id == SessionGrouping.directSessionID
            ? String(localized: "Showing messages sent without a session.")
            : String(localized: "This session is no longer available. Showing its saved messages.")
    }

    private var transcriptEvents: [SessionEvent] {
        stream.usesHistory ? SessionHistoryTranscript.events(sessionID: route.id, messages: store.history)
            : stream.events
    }

    private var sessionAgent: String? {
        guard route.id != SessionGrouping.directSessionID else { return nil }
        return facts.session?.agentName ?? SessionGrouping.groupBySession(store.history)
            .first { $0.id == route.id }?.agentName
    }

    private var earlierEvents: some View {
        VStack(alignment: .leading) {
            if stream.isBackfilling {
                PendingStateView(title: String(localized: "Loading earlier events…"),
                                 onRetry: { await stream.refresh() })
            } else {
                Button("Load earlier events") { Task { await stream.loadEarlier() } }
                    .buttonStyle(.bordered).frame(minHeight: 44)
            }
        }.padding(.vertical, 8)
            .onAppear { Task { await stream.loadEarlier() } }
    }

    private var jumpToLiveButton: some View {
        Button {
            stream.jumpToLive()
            jumpToLatestRequest += 1
        } label: {
            Label(
                stream.pendingWhileLocked > 0
                    ? String(localized: "Jump to live (\(stream.pendingWhileLocked))")
                    : String(localized: "Jump to live"),
                systemImage: "arrow.up.to.line"
            )
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .prominentAction()
        .padding(.bottom, 12)
        .accessibilityIdentifier("jump-to-live")
    }

    private func scrollToLive(_ proxy: ScrollViewProxy) {
        proxy.scrollTo("conversation-start", anchor: .top)
    }

    /// Same reply path and feedback as the Home card, so an answer means the same everywhere.
    private func handleReply(_ choice: String, to id: MessageID) {
        Task {
            if let note = await store.replyWithFeedback(choice, to: id) { actionNote = note }
        }
    }
}
