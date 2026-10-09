// Shared health and coverage copy, plus the original bundled all-clear vector scene.
// Exports: TodaySummary and TodayScene for native light/dark appearance.
// Dependencies: SwiftUI, AppKit SVG image support, and HibossKit TodaySnapshot.

import AppKit
import HibossKit
import SwiftUI

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
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 12) {
            if let url = appResourceBundle.url(forResource: scheme == .dark
                ? "island-night" : "island-day", withExtension: "svg"),
               let image = NSImage(contentsOf: url) {
                SceneImage(image: image).frame(height: 220).clipped()
                    .accessibilityHidden(true)
            }
            Text(L("Nothing needs you")).font(.title2.bold())
            Text(L("You're clear. Agents will show up here when they need a decision."))
                .font(.callout).foregroundStyle(TodayStyle.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .accessibilityIdentifier("today.allClear")
    }
}

// AppKit retains the SVG representation when drawing the bundled vector scene.
private struct SceneImage: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        return view
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 320, height: 220)
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        view.image = image
    }
}
