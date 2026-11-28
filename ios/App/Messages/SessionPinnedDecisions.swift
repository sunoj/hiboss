// The session thread's pinned open decisions: the first answerable in place, the rest one line each.
// Exports: SessionPinnedDecisions and SessionAskedMarker (the in-thread pointer to a pinned card).
// Dependencies: SwiftUI, HibossKit MessageThread, CountdownText, Theme.

import HibossKit
import SwiftUI

struct SessionPinnedDecisions<Card: View>: View {
    let threads: [MessageThread]
    @ViewBuilder let card: (MessageThread) -> Card
    @State private var expanded: Set<MessageID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.xs) {
                Circle().fill(Theme.warn).frame(width: Space.xs, height: Space.xs).accessibilityHidden(true)
                Text("Needs you").font(.headline).accessibilityAddTraits(.isHeader)
                if threads.count > 1 {
                    Text(verbatim: String(threads.count)).font(.headline).foregroundStyle(Theme.ink3)
                }
            }
            ForEach(Array(threads.enumerated()), id: \.element.id) { index, thread in
                if index == 0 || expanded.contains(thread.id) {
                    card(thread)
                        .overlay(RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                            .strokeBorder(Theme.warn, lineWidth: 1.5).allowsHitTesting(false))
                } else {
                    collapsedRow(thread)
                }
            }
        }
    }

    /// A later open decision: its question and deadline; a tap opens it where it stands.
    private func collapsedRow(_ thread: MessageThread) -> some View {
        Button {
            withAnimation(.snappy) { _ = expanded.insert(thread.id) }
        } label: {
            HStack(spacing: Space.s) {
                Text(verbatim: thread.message.messageText.title)
                    .font(.hbSmall.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let deadline = thread.message.expirationDate {
                    CountdownText(deadline: deadline, tint: Theme.warn).font(.footnote).fixedSize()
                } else {
                    Text("No deadline").font(.footnote).foregroundStyle(Theme.ink3).fixedSize()
                }
                Image(systemName: "chevron.down").font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.ink3).accessibilityHidden(true)
            }
            .padding(Space.s)
            .frame(maxWidth: .infinity, minHeight: ControlMetric.minTap, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the choices")
        .accessibilityIdentifier("needs-row-\(thread.id.rawValue)")
    }
}

/// Where a pinned decision sits in time: one line that points up to the pinned card.
struct SessionAskedMarker: View {
    let thread: MessageThread

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            Circle().fill(Theme.warn).frame(width: Space.xs, height: Space.xs).accessibilityHidden(true)
            Text("Asked “\(thread.message.messageText.title)” · pinned above")
                .font(.footnote).foregroundStyle(Theme.ink2).lineLimit(2)
            Spacer(minLength: 0)
            if let date = thread.message.createdDate {
                RecordedTimeText(date: date).font(.caption).foregroundStyle(Theme.ink3).fixedSize()
            }
        }
        .padding(.horizontal, Space.s).padding(.vertical, Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.signalSoft, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("asked-marker-\(thread.id.rawValue)")
    }
}
