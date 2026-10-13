// Today date, native avatar Settings action, and status chips.
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
    @State private var refreshVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(now, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.footnote).foregroundStyle(Theme.ink3)
                    Text("Today").font(.largeTitle.bold())
                }
                Spacer()
                Button(action: onSettings) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.largeTitle).frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("today-settings")
            }
            ViewThatFits(in: .horizontal) {
                HStack { chips }
                VStack(alignment: .leading) { chips }
            }
        }
        .padding(.horizontal, 16)
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
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7).accessibilityHidden(true)
            ZStack(alignment: .leading) {
                if reservesHealthWidth { Text("Checking coverage").hidden() }
                label.lineLimit(1)
            }.font(.footnote).foregroundStyle(Theme.ink2)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Theme.surface, in: Capsule())
    }
}
