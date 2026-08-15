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
                LazyVStack(alignment: .leading, spacing: 0) {
                    if stream.hasEarlier {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .onAppear { Task { await stream.loadEarlier() } }
                    }
                    ForEach(stream.events) { event in
                        SessionTranscriptRow(event: event)
                            .id(event.id)
                    }
                    Color.clear.frame(height: 1).id("live-end")
                }
                .padding(.horizontal, 12)
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

/// Dense transcript line — not a chat bubble.
struct SessionTranscriptRow: View {
    let event: SessionEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Label(directionShort, systemImage: directionSymbol)
                    .labelStyle(.titleAndIcon)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(directionTint)
                    .accessibilityLabel(directionLabel)
                Text(actorLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(event.kind)
                    .font(.caption2)
                    .foregroundStyle(event.isKnownKind ? .tertiary : Color.accentColor)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(timeLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Text(event.displayBody)
                .font(bodyFont)
                .foregroundStyle(event.isKnownKind ? .primary : .secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private var bodyFont: Font {
        if event.isRawOutput { return .callout.monospaced() }
        if !event.isKnownKind { return .caption.monospaced() }
        return .callout
    }

    private var actorLabel: String {
        if let name = event.actorName, !name.isEmpty { return name }
        return directionShort
    }

    private var directionShort: String {
        switch event.direction {
        case "boss_to_agent": return String(localized: "Boss")
        case "agent_to_agent": return String(localized: "Peer")
        case "agent_to_boss": return String(localized: "Agent")
        default: return String(localized: "Event")
        }
    }

    private var directionSymbol: String {
        switch event.direction {
        case "boss_to_agent": return "arrow.left"
        case "agent_to_agent": return "arrow.left.arrow.right"
        case "agent_to_boss": return "arrow.right"
        default: return "questionmark.circle"
        }
    }

    private var directionTint: Color {
        switch event.direction {
        case "boss_to_agent": return Color.accentColor
        case "agent_to_agent": return .secondary
        case "agent_to_boss": return .primary
        default: return .secondary
        }
    }

    private var directionLabel: String {
        switch event.direction {
        case "boss_to_agent": return String(localized: "Boss to agent")
        case "agent_to_agent": return String(localized: "Agent to agent")
        case "agent_to_boss": return String(localized: "Agent to boss")
        default: return String(localized: "Unknown direction")
        }
    }

    private var timeLabel: String {
        guard let date = parseDate(event.createdAt) else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func parseDate(_ value: String) -> Date? {
        (try? Date(value, strategy: .iso8601))
            ?? (try? Date(value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
    }
}
