// The Inbox screen: the pending decision queue, live over SSE.
// Exports: InboxView bound to an InboxStore.
// Dependencies: SwiftUI, HibossKit, MessageCard, ReplySheet, ResolvedDecisionsView.

import HibossKit
import SwiftUI
import UIKit

struct InboxView: View {
    @ObservedObject var store: InboxStore
    @State private var replyTarget: HistoryMessage?
    @State private var actionNote: String?
    @State private var showResolved =
        ProcessInfo.processInfo.environment["HIBOSS_DEMO_RESOLVED"] == "1"

    var body: some View {
        content
            .navigationDestination(isPresented: $showResolved) {
                ResolvedDecisionsView(store: store)
            }
            .sheet(item: $replyTarget) { message in
                ReplySheet(message: message) { choice in
                    await store.reply(choice, to: message.id)
                }
                .presentationDetents([.medium, .large])
            }
            .alert(
                "Heads up",
                isPresented: Binding(get: { actionNote != nil }, set: { if !$0 { actionNote = nil } }),
                presenting: actionNote
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { note in
                Text(note)
            }
    }

    /// Submit a reply and surface a non-success outcome (already-resolved / failed)
    /// so an optimistically-removed card can't silently imply the boss's choice won.
    private func handleReply(_ choice: String, to id: MessageID) {
        Task {
            switch await store.reply(choice, to: id) {
            case .sent:
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            case .alreadyResolved:
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                actionNote = String(localized: "That decision was already answered elsewhere.")
            case .failed:
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                actionNote = String(localized: "Couldn't send your reply — check your connection.")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !store.didLoad && store.history.isEmpty {
            if store.connectionState == .disconnected {
                ContentUnavailableView(
                    "Disconnected",
                    systemImage: "wifi.slash",
                    description: Text("Connect in Settings to receive decisions.")
                )
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if store.pending.isEmpty, store.history.isEmpty, let error = store.loadError {
            ContentUnavailableView {
                Label("Can't reach the server", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { Task { await store.refresh() } }
            }
        } else {
            inboxList
        }
    }

    private var inboxList: some View {
        GeometryReader { geo in
            List {
                if store.pending.isEmpty {
                    allClear
                        .frame(minHeight: InboxResolvedPlacement.allClearHeight(
                            listHeight: geo.size.height,
                            bottomInset: geo.safeAreaInsets.bottom,
                            hasResolved: !store.settledCards.isEmpty
                        ))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                ForEach(store.pending) { message in
                    pendingRow(message)
                }
                if !store.settledCards.isEmpty {
                    resolvedFooter(listHeight: geo.size.height)
                }
            }
            .listStyle(.plain)
            .refreshable { await store.refresh() }
        }
    }

    private func pendingRow(_ message: HistoryMessage) -> some View {
        MessageCard(
            message: message,
            onChoose: { choice in handleReply(choice, to: message.id) },
            onOpen: { AppRouter.shared.open(messageID: message.id.rawValue) }
        )
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button { replyTarget = message } label: {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            trailingSwipes(for: message)
        }
    }

    @ViewBuilder
    private func trailingSwipes(for message: HistoryMessage) -> some View {
        let options = message.options
        if let first = options.first {
            Button { handleReply(first, to: message.id) } label: {
                Label(first, systemImage: MessageMeta.optionIcon(first))
            }
        }
        if options.count >= 2 {
            Button { handleReply(options[1], to: message.id) } label: {
                Label(options[1], systemImage: MessageMeta.optionIcon(options[1]))
            }
        }
        if options.count > 2 {
            Button { replyTarget = message } label: {
                Label("More", systemImage: "ellipsis")
            }
        }
    }

    @ViewBuilder
    private func resolvedFooter(listHeight: CGFloat) -> some View {
        Color.clear
            .frame(height: InboxResolvedPlacement.spacerHeight(
                pendingIsEmpty: store.pending.isEmpty,
                listHeight: listHeight
            ))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
            .accessibilityHidden(true)
        NavigationLink {
            ResolvedDecisionsView(store: store)
        } label: {
            HStack {
                Label("Resolved", systemImage: "checkmark.circle")
                Spacer()
                Text(store.settledCards.count, format: .number)
                    .monospacedDigit()
            }
            .font(.footnote)
            .foregroundStyle(.tertiary)
            .symbolRenderingMode(.hierarchical)
        }
        .tint(Color(.tertiaryLabel))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 12, trailing: 20))
    }

    private var allClear: some View {
        VStack(spacing: 10) {
            AllClearIslandView()
            Text("All clear")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Text("No decisions are waiting on you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
    }
}

enum InboxResolvedPlacement {
    /// The collapsed Resolved row.
    static let label: CGFloat = 44

    /// On an empty queue the all-clear block claims everything above the footer and
    /// centres itself in it, so the island sits in the middle of the free space and the
    /// footer still lands on the bottom edge. Measuring the block instead of estimating
    /// its height is what keeps this correct at larger Dynamic Type sizes.
    ///
    /// `bottomInset` is not optional: the list runs under the floating tab bar, so a
    /// block sized to the raw height pushes the footer beneath it and out of reach.
    static func allClearHeight(listHeight: CGFloat, bottomInset: CGFloat, hasResolved: Bool) -> CGFloat {
        max(160, listHeight - bottomInset - (hasResolved ? label : 0))
    }

    static func spacerHeight(pendingIsEmpty: Bool, listHeight: CGFloat) -> CGFloat {
        pendingIsEmpty ? 0 : 40
    }
}
