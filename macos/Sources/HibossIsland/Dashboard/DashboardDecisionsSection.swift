// Ranked decision preview that stays visible alongside the live Panels workspace.
// Exports: DashboardDecisionsSection with independent loading, connection, and empty states.
// Dependencies: SwiftUI, HibossKit history state, and AttentionRow.

import HibossKit
import SwiftUI

struct DashboardDecisionsSection: View {
    let items: [AttentionItem]
    let now: Date
    let historyState: HistoryState
    let connectionState: ConnectionState
    let limit: Int
    let onSelect: (AttentionItem) -> Void
    let onAll: () -> Void
    let onRetry: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L("Decisions")).font(.title2.bold())
                Text(countLabel).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                if !items.isEmpty { Button(L("View all"), action: onAll) }
            }
            status
            ForEach(Array(items.prefix(limit))) { item in
                Button { onSelect(item) } label: {
                    HStack(alignment: .center, spacing: 12) {
                        AttentionRow(item: item, now: now)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("dashboard.decision.\(item.id.rawValue)")
            }
            if items.count > limit {
                Button(L("View all \(items.count) decisions"), action: onAll)
                    .font(.callout)
            }
        }
        .accessibilityIdentifier("dashboard.decisions")
    }

    private var countLabel: String {
        items.isEmpty && historyState != .loaded ? "—" : "\(items.count)"
    }

    @ViewBuilder
    private var status: some View {
        if case let .failed(message) = historyState {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(.orange)
            Button(L("Try again"), action: onRetry)
        } else if items.isEmpty, connectionState == .disconnected {
            Label(L("Connect to receive agent messages."), systemImage: "antenna.radiowaves.left.and.right.slash")
                .font(.callout).foregroundStyle(.secondary)
            Button(L("Settings"), action: onSettings)
        } else if items.isEmpty, historyState == .loading || historyState == .idle {
            ProgressView(L("Loading…")).controlSize(.small)
        } else if items.isEmpty {
            Label(L("Nothing needs you"), systemImage: "checkmark.circle")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}
