// SwiftUI History window content with v2 toolbar, filtering, and search.
// Exports: HistoryView as the main macOS window surface.
// Dependencies: SwiftUI, HibossKit OptionFlowStore, HistoryRow, and design tokens.

import HibossKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject var flow: OptionFlowStore
    @State private var segment: HistorySegment = .all
    @State private var searchText = ""

    private var unreadCount: Int {
        HistoryMessageLogic.unreadCount(in: flow.historyMessages)
    }

    private var messages: [HistoryMessage] {
        HistoryMessageLogic.filtered(
            flow.historyMessages,
            segment: segment,
            searchText: searchText
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbarRow
            Divider().overlay(Color(nsColor: .separatorColor))
            historyContent
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            if flow.historyState == .idle { await flow.refreshHistory() }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                connectionAccessory
            }
        }
    }

    private var toolbarRow: some View {
        HStack(spacing: 12) {
            segmentedFilter
            Spacer(minLength: 12)
            searchField
            refreshButton
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var segmentedFilter: some View {
        HStack(spacing: 2) {
            ForEach(HistorySegment.allCases) { item in
                Button { segment = item } label: {
                    Text(item.title(unreadCount: unreadCount))
                        .font(.system(size: 12, weight: segment == item ? .medium : .regular))
                        .foregroundStyle(segment == item ? Color.primary : Color.secondary)
                        .padding(.horizontal, 13)
                        .frame(height: 28)
                        .background(segment == item ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.tile))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.notice))
    }

    private var searchField: some View {
        TextField("Search messages…", text: $searchText)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 10)
            .frame(width: 210, height: 30)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.notice))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.notice)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            )
    }

    private var connectionAccessory: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(flow.connectionState == .connected ? DesignTokens.live : Color.secondary)
                .frame(width: 7, height: 7)
            Text(connectionLabel)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(flow.connectionState == .connected ? DesignTokens.live : Color.secondary)
        }
    }

    private var refreshButton: some View {
        Button {
            Task { await flow.refreshHistory() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.secondary)
                .frame(width: 30, height: 30)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.notice))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.notice)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help("Refresh messages")
        .disabled(flow.historyState == .loading)
    }

    @ViewBuilder
    private var historyContent: some View {
        if flow.historyMessages.isEmpty, flow.historyState == .loading {
            ProgressView("Loading messages…")
                .foregroundStyle(Color.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if flow.historyMessages.isEmpty || messages.isEmpty {
            ContentUnavailableView(
                emptyTitle,
                systemImage: emptySystemImage,
                description: Text(emptyDescription)
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 9) {
                    ForEach(messages) { message in
                        HistoryRow(message: message)
                    }
                }
                .padding(18)
            }
        }
    }

    private var connectionLabel: String {
        flow.connectionState == .connected ? "SSE CONNECTED" : flow.connectionState.label.uppercased()
    }

    private var emptyTitle: String {
        if case .failed = flow.historyState { return "History Unavailable" }
        return messages.isEmpty && !flow.historyMessages.isEmpty ? "No Matching Messages" : "No Messages"
    }

    private var emptySystemImage: String {
        if case .failed = flow.historyState { return "exclamationmark.triangle" }
        return "tray"
    }

    private var emptyDescription: String {
        if case let .failed(message) = flow.historyState { return message }
        if messages.isEmpty && !flow.historyMessages.isEmpty {
            return "Try a different filter or search."
        }
        return "Agent messages will appear here."
    }
}
