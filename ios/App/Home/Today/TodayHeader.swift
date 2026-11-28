// Today date, one summary line of counts and the connection chip; HomeView owns the title.
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
    @State private var refreshVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if showsDate {
                Text(now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.footnote).foregroundStyle(Theme.ink3)
            }
            // One line when it fits; the connection chip drops below the counts otherwise.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.s) {
                    summary
                    Spacer(minLength: Space.xs)
                    healthChip
                }
                VStack(alignment: .leading, spacing: Space.xs) {
                    summary
                    healthChip
                }
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

    /// "3 need you · 2 working": each count is its own text, coloured by its meaning.
    @ViewBuilder private var summary: some View {
        let parts = summaryParts
        if !parts.isEmpty {
            HStack(spacing: Space.xxs) {
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                    if index > 0 { Text(verbatim: "·").foregroundStyle(Theme.ink3).accessibilityHidden(true) }
                    part
                }
            }
            .font(.hbSmall.weight(.semibold))
            .lineLimit(1)
        }
    }

    private var summaryParts: [Text] {
        var parts: [Text] = []
        if !inputsLoaded {
            parts.append(Text("Loading").foregroundColor(Theme.ink3))
        } else if requestCount > 0 {
            parts.append(Text("\(String(requestCount)) need you").foregroundColor(Theme.warn))
        }
        if !snapshot.working.isEmpty {
            parts.append(Text("\(String(snapshot.working.count)) working").foregroundColor(Theme.live))
        }
        return parts
    }

    @ViewBuilder private var healthChip: some View {
        if refreshVisible {
            chip(Text("Refreshing…"), color: Theme.live)
        } else if case .live(let checkedAt) = snapshot.health, snapshot.coverageComplete {
            chip(Text("Live") + Text(verbatim: " · ") + Text(verbatim: RelativeTime.short(from: checkedAt,
                                                                                     now: now)),
                 color: Theme.positive)
        } else {
            switch snapshot.health {
            case .connecting: chip(Text("Connecting…"), color: Theme.ink3)
            case .offline: chip(Text("Not connected"), color: Theme.warn)
            case .loading, .live: chip(Text("Checking coverage"), color: Theme.ink3)
            }
        }
    }

    private func chip(_ label: Text, color: Color) -> some View {
        HStack(spacing: Space.xs) {
            Circle().fill(color).frame(width: Space.xs, height: Space.xs).accessibilityHidden(true)
            label.fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote).foregroundStyle(Theme.ink2)
        .padding(.horizontal, Space.s).padding(.vertical, Space.xs)
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
