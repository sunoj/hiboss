// Today date and status chips; HomeView owns the navigation title and Settings action.
// Exports TodayHeader and TodayHeaderLayout; counts come directly from the shared snapshot.
// Dependencies: SwiftUI, HibossKit TodaySnapshot, and Theme.

import HibossKit
import SwiftUI

struct TodayHeader: View {
    let snapshot: TodaySnapshot
    let requestCount: Int
    var inputsLoaded = true
    var isRefreshing = false
    let now: Date
    /// A short container moves the date into the navigation subtitle (see TodayHeaderLayout).
    var showsDate = true
    let onSettings: () -> Void
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var refreshVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if showsDate {
                Text(now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.footnote).foregroundStyle(Theme.ink3)
            }
            // Never truncate: one row, then one row with tighter chips, then wrapped rows.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.xs) { chips(inset: Space.s) }
                HStack(spacing: Space.xs) { chips(inset: Space.xs) }
                DecisionOptionFlow(layoutDirection: layoutDirection) { chips(inset: Space.xs) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.m)
        .task(id: isRefreshing) {
            refreshVisible = false
            guard isRefreshing else { return }
            do { try await Task.sleep(for: PendingTiming.revealDelay) }
            catch { return }
            refreshVisible = true
        }
    }

    @ViewBuilder private func chips(inset: CGFloat) -> some View {
        if !inputsLoaded {
            chip(Text("Loading"), color: Theme.ink3, inset: inset)
        } else if requestCount > 0 {
            chip(Text("\(String(requestCount)) need you"), color: Theme.warn, inset: inset)
        }
        if !snapshot.working.isEmpty {
            chip(Text("\(String(snapshot.working.count)) working"), color: Theme.positive, inset: inset)
        }
        if refreshVisible {
            chip(Text("Refreshing…"), color: Theme.live, inset: inset, reservesHealthWidth: true)
        } else if case .live(let checkedAt) = snapshot.health, snapshot.coverageComplete {
            chip(Text("Live") + Text(verbatim: " · ") + Text(verbatim: RelativeTime.short(from: checkedAt,
                                                                                     now: now)),
                 color: Theme.positive, inset: inset, reservesHealthWidth: true)
        } else {
            switch snapshot.health {
            case .connecting:
                chip(Text("Connecting…"), color: Theme.ink3, inset: inset, reservesHealthWidth: true)
            case .offline:
                chip(Text("Not connected"), color: Theme.warn, inset: inset, reservesHealthWidth: true)
            case .loading, .live:
                chip(Text("Checking coverage"), color: Theme.ink3, inset: inset, reservesHealthWidth: true)
            }
        }
    }

    private func chip(_ label: Text, color: Color, inset: CGFloat,
                      reservesHealthWidth: Bool = false) -> some View {
        HStack(spacing: Space.xs) {
            Circle().fill(color).frame(width: Space.xs, height: Space.xs).accessibilityHidden(true)
            ZStack(alignment: .leading) {
                // Holds the routine Live ↔ Refreshing flip steady; rarer states may reflow the row.
                if reservesHealthWidth { Text("Refreshing…").lineLimit(1).hidden() }
                label.fixedSize(horizontal: false, vertical: true)
            }.font(.footnote).foregroundStyle(Theme.ink2)
        }
        .padding(.horizontal, inset).padding(.vertical, Space.xs)
        .background(Theme.surface, in: Capsule())
    }
}

/// Today's header on a short container: below the threshold the date leaves the content for the
/// navigation subtitle, so the first decision starts higher. Keyed on size, never on device.
enum TodayHeaderLayout {
    /// Full container height, safe areas included, at or below which the header compacts.
    static let compactHeight: CGFloat = 700

    static func isCompact(containerHeight: CGFloat) -> Bool {
        containerHeight > 0 && containerHeight <= compactHeight
    }

    /// Whether the date moves: it needs both a short container and a navigation subtitle.
    static func movesDate(containerHeight: CGFloat) -> Bool {
        guard #available(iOS 26, *) else { return false }
        return isCompact(containerHeight: containerHeight)
    }
}

extension View {
    /// Shows Today's date as the navigation subtitle when the header has given it up.
    @ViewBuilder func todayDateSubtitle(_ date: Date, shown: Bool) -> some View {
        if shown, #available(iOS 26, *) {
            navigationSubtitle(Text(date, format: .dateTime.weekday(.wide).day().month(.wide)))
        } else {
            self
        }
    }
}
