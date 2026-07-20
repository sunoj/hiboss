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
            Divider().overlay(DesignTokens.line)
            historyContent
        }
        .background(DesignTokens.paper)
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
                        .foregroundStyle(segment == item ? DesignTokens.ink : DesignTokens.ink3)
                        .padding(.horizontal, 13)
                        .frame(height: 28)
                        .background(segment == item ? DesignTokens.surface : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.control))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(DesignTokens.surface2)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.segment))
    }

    private var searchField: some View {
        TextField("Search messages…", text: $searchText)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(DesignTokens.ink)
            .padding(.horizontal, 10)
            .frame(width: 210, height: 30)
            .background(DesignTokens.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.segment))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.segment)
                    .strokeBorder(DesignTokens.line2, lineWidth: 1)
            )
    }

    private var connectionAccessory: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(flow.connectionState == .connected ? DesignTokens.statusLight : DesignTokens.ink3)
                .frame(width: 7, height: 7)
            Text(connectionLabel)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(flow.connectionState == .connected ? DesignTokens.pos : DesignTokens.ink3)
        }
    }

    private var refreshButton: some View {
        Button {
            Task { await flow.refreshHistory() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DesignTokens.ink2)
                .frame(width: 30, height: 30)
                .background(DesignTokens.surface)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.segment))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.segment)
                        .strokeBorder(DesignTokens.line2, lineWidth: 1)
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
                .foregroundStyle(DesignTokens.ink2)
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
