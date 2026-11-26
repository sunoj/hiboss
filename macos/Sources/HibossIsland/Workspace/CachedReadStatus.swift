// A reserved status label annotates cached surfaces without inserting content rows.
// Exports CachedReadStatus with delayed refresh copy and a compact retry action.
// Its age ticks only when the shown text can change, never for a static label.
// Dependencies: SwiftUI and the shared elapsed-time formatter.

import SwiftUI

struct CachedReadStatus: View {
    let isRefreshing: Bool
    var updatedAt: Date?
    var failure: String?
    var retry: (() -> Void)?
    @StateObject private var refreshStatus = RefreshStatus()
    @Environment(\.surfaceIsVisible) private var isVisible

    var body: some View {
        HStack(spacing: 6) {
            if let updatedAt, failure == nil, !refreshStatus.showsUpdating {
                TimelineView(ElapsedLabelSchedule(since: updatedAt).paused(!isVisible)) { tick in
                    label(status(at: tick.date))
                }
            } else {
                label(status(at: .now))
            }
            if failure != nil, let retry { Button(L("Retry"), action: retry) }
        }
        .font(.caption).foregroundStyle(.secondary)
        .help(failure ?? "")
        .task(id: isRefreshing) {
            await refreshStatus.update(isRefreshing: isRefreshing)
        }
        .accessibilityIdentifier("workspace.readStatus")
    }

    private func label(_ text: String) -> some View {
        Text(text).lineLimit(1).frame(width: 160, alignment: .leading)
    }

    private func status(at now: Date) -> String {
        if failure != nil { return L("Update failed") }
        if refreshStatus.showsUpdating { return L("Updating…") }
        if let updatedAt { return L("Updated \(AttentionClock.elapsed(since: updatedAt, now: now, coarse: true)) ago") }
        return ""
    }
}

extension ToolbarContent {
    @ToolbarContentBuilder
    func quietStatusBackground() -> some ToolbarContent {
        if #available(macOS 26, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}
