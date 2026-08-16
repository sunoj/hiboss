// Real-time session transcript: append-only events with scroll lock.
// Exports: SessionMessagesView bound to SessionStreamStore and SessionRoute.
// Dependencies: SwiftUI, HibossKit SessionStreamStore, system semantic styles.

import HibossKit
import SwiftUI

struct SessionMessagesView: View {
    let route: SessionRoute
    let api: (any SessionStreamServing)?

    @StateObject private var stream: SessionStreamStore
    @Environment(\.scenePhase) private var scenePhase

    init(route: SessionRoute, api: (any SessionStreamServing)?) {
        self.route = route
        self.api = api
        _stream = StateObject(wrappedValue: SessionStreamStore(sessionID: route.id))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            content
            if !stream.isFollowingLive {
                jumpToLiveButton
            }
        }
        .navigationTitle(route.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ConnectionDot(state: stream.connectionState)
            }
        }
        .task(id: route.id) {
            if let api { stream.start(api: api) }
        }
        .onDisappear { stream.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { stream.resumeFromForeground() }
        }
        .refreshable { await stream.refresh() }
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
    }

    @ViewBuilder
    private var content: some View {
        if stream.isLoading && stream.events.isEmpty {
            ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = stream.loadError, stream.events.isEmpty {
            ContentUnavailableView(
                String(localized: "Couldn't load transcript"),
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
        } else if stream.events.isEmpty {
            ContentUnavailableView(
                String(localized: "No events yet"),
                systemImage: "text.alignleft",
                description: Text(String(localized: "This session has no transcript events yet."))
            )
        } else {
            transcript
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if stream.hasEarlier {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .onAppear { Task { await stream.loadEarlier() } }
                    }
                    ForEach(SessionTranscriptLayout.items(from: stream.events)) { item in
                        SessionTranscriptItemView(item: item)
                            .id(item.id)
                    }
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
            .onChange(of: stream.isFollowingLive) { _, following in
                if following { scrollToLive(proxy) }
            }
        }
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
        .buttonStyle(.borderedProminent)
        .padding(.bottom, 12)
        .accessibilityIdentifier("jump-to-live")
    }

    private func scrollToLive(_ proxy: ScrollViewProxy) {
        proxy.scrollTo("live-end", anchor: .bottom)
    }
}
