// Today date and status chips; HomeView owns the navigation title and Settings action.
// Exports TodayHeader; counts come directly from the shared snapshot.
// Dependencies: SwiftUI, HibossKit TodaySnapshot, and Theme.

import HibossKit
import SwiftUI

struct TodayHeader: View {
    let snapshot: TodaySnapshot
    let requestCount: Int
    var inputsLoaded = true
    var isRefreshing = false
    let now: Date
    let onSettings: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var refreshVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(now, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.footnote).foregroundStyle(Theme.ink3)
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.xs) { chips }.fixedSize(horizontal: true, vertical: false)
                }
            } else {
                HStack(spacing: Space.xs) { chips }
            }
        }
        .padding(.horizontal, Space.m)
        .task(id: isRefreshing) {
            refreshVisible = false
            guard isRefreshing else { return }
            do { try await Task.sleep(for: PendingTiming.revealDelay) }
            catch { return }
            refreshVisible = true
        }
    }

    @ViewBuilder private var chips: some View {
        if !inputsLoaded {
            chip(Text("Loading"), color: Theme.ink3)
        } else if requestCount > 0 {
            chip(Text("\(String(requestCount)) need you"), color: Theme.warn)
        }
        if !snapshot.working.isEmpty {
            chip(Text("\(String(snapshot.working.count)) working"), color: Theme.positive)
        }
        if refreshVisible {
            chip(Text("Refreshing…"), color: Theme.live, reservesHealthWidth: true)
        } else if case .live(let checkedAt) = snapshot.health, snapshot.coverageComplete {
            chip(Text("Live") + Text(verbatim: " · ") + Text(verbatim: RelativeTime.short(from: checkedAt,
                                                                                     now: now)),
                 color: Theme.positive, reservesHealthWidth: true)
        } else {
            switch snapshot.health {
            case .connecting:
                chip(Text("Connecting…"), color: Theme.ink3, reservesHealthWidth: true)
            case .offline:
                chip(Text("Not connected"), color: Theme.warn, reservesHealthWidth: true)
            case .loading, .live:
                chip(Text("Checking coverage"), color: Theme.ink3, reservesHealthWidth: true)
            }
        }
    }

    private func chip(_ label: Text, color: Color, reservesHealthWidth: Bool = false) -> some View {
        HStack(spacing: Space.xs) {
            Circle().fill(color).frame(width: Space.xs, height: Space.xs).accessibilityHidden(true)
            ZStack(alignment: .leading) {
                if reservesHealthWidth { Text("Checking coverage").hidden() }
                label.lineLimit(1)
            }.font(.footnote).foregroundStyle(Theme.ink2)
        }
        .padding(.horizontal, Space.s).padding(.vertical, Space.xs)
        .background(Theme.surface, in: Capsule())
    }
}
