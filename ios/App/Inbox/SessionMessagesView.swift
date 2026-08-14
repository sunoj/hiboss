// Session thread: every message in one conversation, oldest at top, scroll up.
// Exports: SessionMessagesView bound to an InboxStore and SessionRoute.
// Dependencies: SwiftUI, HibossKit SessionGrouping, ThreadBubble.

import HibossKit
import SwiftUI

struct SessionMessagesView: View {
    @ObservedObject var store: InboxStore
    let route: SessionRoute
    @State private var expandedID: MessageID?

    private var messages: [HistoryMessage] {
        store.messages(inSession: route.id)
    }

    var body: some View {
        Group {
            if messages.isEmpty {
                ContentUnavailableView(
                    "No messages",
                    systemImage: "tray",
                    description: Text("This session has no messages yet.")
                )
            } else {
                thread
            }
        }
        .refreshable { await store.refresh() }
        .navigationTitle(route.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { message in
                        ThreadBubble(
                            message: message,
                            expanded: expandedID == message.id
                        )
                        .id(message.id)
                        .onTapGesture {
                            expandedID = expandedID == message.id ? nil : message.id
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onAppear {
                expandedID = messages.last(where: { $0.direction == "boss_to_agent" })?.id
                scrollToLatest(proxy)
            }
            .onChange(of: messages.count) { _, _ in scrollToLatest(proxy) }
        }
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        guard let last = messages.last else { return }
        proxy.scrollTo(last.id, anchor: .bottom)
    }
}

/// One bubble in a session thread. Agent on the leading edge, boss on the trailing.
struct ThreadBubble: View {
    let message: HistoryMessage
    var expanded: Bool = false

    private var fromBoss: Bool { message.direction == "boss_to_agent" }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if fromBoss { Spacer(minLength: 48) }
            VStack(alignment: fromBoss ? .trailing : .leading, spacing: 4) {
                Text(message.body)
                    .font(.body)
                    .foregroundStyle(fromBoss ? Color(.systemBackground) : .primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                if fromBoss, let parentHint {
                    Text(parentHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if expanded {
                    MessageMetaStrip(message: message, density: .selected)
                }
                if !message.relativeCreatedAt.isEmpty {
                    Text(message.relativeCreatedAt)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            if !fromBoss { Spacer(minLength: 48) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows message details")
    }

    /// A short "You chose …" cue so a boss reply reads as a turn, not a stray bubble.
    private var parentHint: String? {
        guard message.replyTo != nil else { return nil }
        if let source = resolutionSourceLabel(message.metadata?.source) {
            return String(localized: "Choice · \(source)")
        }
        return String(localized: "Choice")
    }

    private var fill: Color {
        fromBoss ? Color.accentColor : Color(.secondarySystemFill)
    }
}
