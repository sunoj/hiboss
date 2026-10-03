// Full-width decision row with readable context and a discoverable open action.
// Exports: DashboardDecisionRow with native button keyboard behavior.
// Dependencies: SwiftUI, AttentionItem, AttentionClock.

import SwiftUI

struct DashboardDecisionRow: View {
    let item: AttentionItem
    let now: Date
    let onSelect: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold)).foregroundStyle(Color.accentColor)
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.body).font(.body.weight(.semibold)).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(item.project + " · " + item.asker)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let content = item.content {
                        Text(content).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                    TimelineView(.periodic(from: now, by: 1)) { context in
                        timing(at: context.date)
                    }
                }
                Image(systemName: "arrow.up.right")
                    .font(.callout).foregroundStyle(.secondary).padding(.top, 6)
            }
            .padding(.vertical, 16).padding(.horizontal, 12)
            .contentShape(Rectangle())
            .background(Color.primary.opacity(hovering ? 0.045 : 0), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovering)
        .accessibilityIdentifier("dashboard.decision.\(item.id.rawValue)")
        .accessibilityHint(L("Open decision"))
    }

    private var symbol: String {
        if item.isRunningAutoDecision(at: now) { return "timer" }
        return item.priorityRank < 2 ? "exclamationmark.bubble" : "bubble.left"
    }

    private func timing(at date: Date) -> some View {
        Group {
            if let remaining = item.remaining(at: date), let option = item.defaultOption {
                Text(L("Chooses \(option) in \(remaining)"))
            } else {
                Text(L("Waiting \(item.waited(at: date))"))
            }
        }
        .font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
    }
}
