// Real-time session transcript: append-only events with scroll lock and in-place decisions.
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
    @State private var hasLoaded = false
    @State private var actionNote: String?

    init(route: SessionRoute, api: (any SessionStreamServing)?, store: InboxStore,
         panels: PanelsModel? = nil) {
        self.panels = panels
        self.route = route
        self.api = api
        self.store = store
        _stream = StateObject(wrappedValue: SessionStreamStore(sessionID: route.id))
    }

    private var connectedTranscript: some View {
        VStack(spacing: 0) {
            if let session = facts.session {
                SessionFactsHeader(session: session).padding(12).background(Theme.paper)
            }
            ZStack(alignment: .bottom) {
                content.clipped()
                if !stream.isFollowingLive {
                    jumpToLiveButton
                }
            }
        }
        .background(Theme.paper)
        .safeAreaInset(edge: .bottom) { SessionReplyComposer(target: newestAgentMessageID, store: store) }
        .navigationTitle(Text(verbatim: route.label))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { historyToolbar }
        .task(id: route.id) {
            if let api { stream.start(api: api) }
            await facts.load(id: route.id, api: store.api as? any SessionsServing)
        }
        .onDisappear { stream.stop() }
        .onChange(of: store.replyConfirmation) { _, confirmation in
            if confirmation != nil { Task { await stream.refresh() } }
        }
        .onChange(of: stream.connectionState, initial: true) { _, state in
            if state == .connected || stream.loadError != nil { hasLoaded = true }
        }
        .onChange(of: stream.isLoading) { _, loading in
            if !loading { hasLoaded = true }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { stream.resumeFromForeground() }
        }
        .refreshable {
            await stream.refresh()
            await facts.load(id: route.id, api: store.api as? any SessionsServing)
            if let panels { await panels.load() }
        }
    }

    private var historyToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack {
                NavigationLink {
                    MessagesView(store: store, sessionID: route.id).navigationTitle("Messages")
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }.accessibilityLabel("Message history")
                ConnectionDot(state: stream.connectionState)
            }
        }
    }

    var body: some View {
        connectedTranscript
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

    private var newestAgentMessageID: MessageID? {
        stream.events.last { $0.kind == "message" && $0.direction == "agent_to_boss" && $0.messageId != nil }
            .flatMap { $0.messageId }.map { MessageID(rawValue: $0) }
    }

    private var content: some View {
        ListStateView(
            isLoading: !hasLoaded || stream.isLoading, error: stream.loadError,
            isEmpty: stream.events.isEmpty,
            emptyIcon: "text.alignleft", emptyTitle: String(localized: "No events yet"),
            emptyDetail: String(localized: "This session has no transcript events yet."),
            loadingTitle: String(localized: "Loading transcript…"),
            hasLoaded: hasLoaded,
            onRetry: { await stream.refresh() }
        ) { transcript }
        .safeAreaInset(edge: .bottom) {
            if !stream.events.isEmpty, stream.connectionState != .connected {
                PendingStateView(
                    title: String(localized: "Reconnecting transcript. Showing earlier events."),
                    onRetry: { await stream.refresh() }
                ).padding(12).background(.bar)
            }
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let error = facts.error {
                        Text(verbatim: error).font(.footnote).foregroundStyle(Theme.ink2)
                        RetryButton { await facts.load(id: route.id, api: store.api as? any SessionsServing) }
                    }
                    if stream.hasEarlier {
                        earlierEvents
                    }
                    ForEach(SessionTranscriptLayout.items(from: stream.events)) { item in
                        SessionTranscriptItemView(item: item, store: store, onChoose: handleReply)
                            .id(item.id)
                    }
                    if let panels { SessionPanelCards(sessionID: route.id, model: panels) }
                    Color.clear.frame(height: 1).id("live-end")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .coordinateSpace(name: "transcript")
            .simultaneousGesture(
                DragGesture(minimumDistance: 8).onChanged { value in
                    if value.translation.height > 12 {
                        stream.readerScrolledAway()
                    }
                }
            )
            .onAppear { scrollToLive(proxy) }
            .onChange(of: stream.events.last?.sequence) { _, _ in
                if stream.isFollowingLive { scrollToLive(proxy) }
            }
            .onChange(of: panels?.tiles.count) { _, _ in
                if stream.isFollowingLive { scrollToLive(proxy) }
            }
            .onChange(of: stream.isFollowingLive) { _, following in
                if following { scrollToLive(proxy) }
            }
        }
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
        } label: {
            Label(
                stream.pendingWhileLocked > 0
                    ? String(localized: "Jump to live (\(stream.pendingWhileLocked))")
                    : String(localized: "Jump to live"),
                systemImage: "arrow.down.to.line"
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
        proxy.scrollTo("live-end", anchor: .bottom)
    }

    /// Same reply path and feedback as the Home card, so an answer means the same everywhere.
    private func handleReply(_ choice: String, to id: MessageID) {
        Task {
            if let note = await store.replyWithFeedback(choice, to: id) { actionNote = note }
        }
    }
}
