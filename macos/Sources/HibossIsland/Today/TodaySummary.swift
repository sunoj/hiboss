// Shared health, coverage copy, and a compact all-clear illustration.
// Exports: TodaySummary and TodayScene for native light/dark appearance.
// Dependencies: SwiftUI and HibossKit TodaySnapshot and TodayIdleIllustration.

import HibossKit
import SwiftUI
import AppKit

struct TodaySummary: View {
    let snapshot: TodaySnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.caption).foregroundStyle(TodayStyle.tertiary)
            Text(L("Today")).font(.title.bold())
            HStack(spacing: 16) {
                if !snapshot.decisions.isEmpty {
                    Label(L("\(snapshot.decisions.count) need you"), systemImage: "circle.fill")
                        .foregroundStyle(TodayStyle.signal)
                }
                if !snapshot.working.isEmpty {
                    Label(L("\(snapshot.working.count) working"), systemImage: "circle.fill")
                        .foregroundStyle(TodayStyle.live)
                }
            }.font(.callout)
            if case let .live(checkedAt) = snapshot.health {
                TimelineView(.periodic(from: now, by: 1)) { context in
                    let age = AttentionClock.elapsed(since: checkedAt, now: context.date)
                    Label(L("Live · updated \(age) ago"), systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(TodayStyle.settled)
                }
            } else {
                Label(healthText, systemImage: "antenna.radiowaves.left.and.right.slash")
                    .font(.callout).foregroundStyle(TodayStyle.secondary)
            }
            if !snapshot.coverageComplete {
                Text(L("Coverage is incomplete. Older decisions may not be visible."))
                    .font(.callout).foregroundStyle(TodayStyle.secondary)
            }
        }
    }

    private var healthText: String {
        switch snapshot.health {
        case .loading: L("Loading messages…")
        case .connecting: L("Connecting…")
        case .offline: L("Connection interrupted. Showing recent messages.")
        case .live: L("Live")
        }
    }
}

struct TodayScene: View {
    var body: some View {
        HStack(spacing: 16) {
            TodaySceneImage().frame(width: 120, height: 72)
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Nothing needs you")).font(.headline)
                Text(L("You're clear. Agents will show up here when they need a decision."))
                    .font(.callout).foregroundStyle(TodayStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
        .accessibilityIdentifier("today.allClear")
    }
}

private struct TodaySceneImage: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> NSImageView {
        let image = NSImageView()
        image.imageScaling = .scaleProportionallyUpOrDown
        return image
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        let renderer = ImageRenderer(content: TodayIdleIllustration(
            ink: TodayStyle.secondary, accent: TodayStyle.settled).environment(\.colorScheme, colorScheme))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        view.image = renderer.nsImage
    }
}
