// A reserved status label annotates cached surfaces without inserting content rows.
// Exports CachedReadStatus with delayed refresh copy and a compact retry action.
// Dependencies: SwiftUI and the shared elapsed-time formatter.

import SwiftUI

struct CachedReadStatus: View {
    let isRefreshing: Bool
    var updatedAt: Date?
    var failure: String?
    var retry: (() -> Void)?
    @StateObject private var refreshStatus = RefreshStatus()

    var body: some View {
        HStack(spacing: 6) {
            TimelineView(.periodic(from: .now, by: 1)) { tick in
                Text(status(at: tick.date)).lineLimit(1)
                    .frame(width: 160, alignment: .leading)
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

    private func status(at now: Date) -> String {
        if failure != nil { return L("Update failed") }
        if refreshStatus.showsUpdating { return L("Updating…") }
        if let updatedAt { return L("Updated \(AttentionClock.elapsed(since: updatedAt, now: now)) ago") }
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
