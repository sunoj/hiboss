// The window's one connection and freshness chip: "Live · updated 6s ago", or what went wrong.
// Exports: ToolbarLiveChip and its pure text/tone policy (ToolbarLiveChip.State).
// Dependencies: SwiftUI, HibossKit ConnectionState, RefreshStatus, and TodayStyle colours.

import HibossKit
import SwiftUI

struct ToolbarLiveChip: View {
    let connection: ConnectionState
    var updatedAt: Date?
    var isRefreshing = false
    var failure: String?
    var retry: (() -> Void)?
    @StateObject private var refreshStatus = RefreshStatus()
    @Environment(\.surfaceIsVisible) private var isVisible

    enum Tone: Equatable { case live, quiet, failed }

    /// What the chip says, without the ticking age; `age` is filled in only for `.live`.
    enum State: Equatable {
        case live(since: Date?), updating, connection(String), failed

        static func of(_ connection: ConnectionState, updatedAt: Date?, showsUpdating: Bool,
                       failure: String?) -> State {
            if failure != nil { return .failed }
            guard connection == .connected else { return .connection(connection.label) }
            return showsUpdating ? .updating : .live(since: updatedAt)
        }

        func text(now: Date) -> String {
            switch self {
            case let .live(since?):
                L("Live · updated \(AttentionClock.elapsed(since: since, now: now, coarse: true)) ago")
            case .live(nil): L("Live")
            case .updating: L("Updating…")
            case let .connection(label): label
            case .failed: L("Update failed")
            }
        }

        var tone: Tone {
            switch self {
            case .live, .updating: .live
            case .connection: .quiet
            case .failed: .failed
            }
        }
    }

    var body: some View {
        let state = State.of(connection, updatedAt: updatedAt,
            showsUpdating: refreshStatus.showsUpdating, failure: failure)
        HStack(spacing: 6) {
            Circle().fill(color(state.tone)).frame(width: 7, height: 7)
            if case let .live(since?) = state {
                TimelineView(ElapsedLabelSchedule(since: since).paused(!isVisible)) { tick in
                    Text(state.text(now: tick.date))
                }
            } else {
                Text(state.text(now: .now))
            }
            if state == .failed, let retry {
                Button(L("Retry"), action: retry).buttonStyle(.link)
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(color(state.tone))
        .lineLimit(1)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(background(state.tone), in: Capsule())
        .fixedSize()
        .help(failure ?? connection.detail ?? connection.label)
        .task(id: isRefreshing) { await refreshStatus.update(isRefreshing: isRefreshing) }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("workspace.readStatus")
        .layoutProbe("workspace.live")
    }

    private func color(_ tone: Tone) -> Color {
        switch tone {
        case .live: TodayStyle.settled
        case .quiet: TodayStyle.secondary
        case .failed: TodayStyle.signal
        }
    }

    private func background(_ tone: Tone) -> Color {
        switch tone {
        case .live: TodayStyle.settledSoft
        case .quiet: TodayStyle.hairline.opacity(0.6)
        case .failed: TodayStyle.signalSoft
        }
    }
}
