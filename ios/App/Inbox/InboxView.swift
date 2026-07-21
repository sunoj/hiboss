// The Inbox screen: pending decisions and full history, live over SSE.
// Exports: InboxView bound to an InboxStore.
// Dependencies: SwiftUI, HibossKit, MessageCard, and the theme tokens.

import HibossKit
import SwiftUI

struct InboxView: View {
    @ObservedObject var store: InboxStore
    @State private var tab: Tab = .pending
    @State private var replyTarget: HistoryMessage?
    var onOpenSettings: () -> Void

    enum Tab { case pending, all }

    var body: some View {
        VStack(spacing: 0) {
            head
            content
        }
        .background(Theme.paper.ignoresSafeArea())
        .sheet(item: $replyTarget) { message in
            ReplySheet(message: message) { choice in
                Task { await store.reply(choice, to: message.id) }
            }
            .presentationDetents([.height(280)])
        }
    }

    private var head: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Inbox").font(.hbLargeTitle).foregroundStyle(Theme.ink)
                Spacer()
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.ink2)
                        .frame(width: 36, height: 36)
                        .background(Theme.surface2)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Text(subtitle)
                .font(.hbFootnote)
                .foregroundStyle(Theme.ink3)
                .padding(.top, 2)
            segmented.padding(.top, 16)
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    private var subtitle: String {
        let count = store.pendingCount
        let waiting = count == 0 ? "No messages waiting" :
            "\(count) message\(count == 1 ? "" : "s") waiting for you"
        return "\(waiting) · \(store.connectionState.label)"
    }

    private var segmented: some View {
        HStack(spacing: 2) {
            segment(title: "Pending · \(store.pendingCount)", selected: tab == .pending) { tab = .pending }
            segment(title: "All", selected: tab == .all) { tab = .all }
        }
        .padding(3)
        .background(Theme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func segment(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? Theme.ink : Theme.ink3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(selected ? Theme.surface : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .shadow(color: selected ? Color.black.opacity(0.06) : .clear, radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if tab == .pending {
            pendingContent
        } else {
            allHistoryContent
        }
    }

    private var sessionGroups: [SessionGroup] {
        SessionGrouping.groupBySession(store.history)
    }

    private var pendingContent: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if store.pending.isEmpty {
                    EmptyState(
                        icon: "checkmark.circle",
                        title: "All clear",
                        detail: "No decisions are waiting on you."
                    ).padding(.top, 80)
                } else {
                    ForEach(store.pending) { message in
                        MessageCard(
                            message: message,
                            onChoose: { choice in Task { await store.reply(choice, to: message.id) } },
                            onMore: { replyTarget = message }
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .padding(.bottom, 96)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var allHistoryContent: some View {
        if store.history.isEmpty {
            ScrollView {
                EmptyState(
                    icon: "tray",
                    title: "No messages yet",
                    detail: "Agent messages will appear here."
                ).padding(.top, 80)
            }
            .scrollIndicators(.hidden)
        } else {
            List {
                ForEach(sessionGroups) { group in
                    Section {
                        ForEach(group.messages) { message in
                            HistoryRow(message: message)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    } header: {
                        SessionSectionHeader(group: group)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 96) }
        }
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.ink4)
            Text(title).font(.hbH3).foregroundStyle(Theme.ink2)
            Text(detail).font(.hbCaption).foregroundStyle(Theme.ink3)
        }
        .frame(maxWidth: .infinity)
    }
}
