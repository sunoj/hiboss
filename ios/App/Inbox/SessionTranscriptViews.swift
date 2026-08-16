// SMS-style rows for a session stream: bubbles, centred system lines, time stamps.
// Exports: SessionTranscriptItemView and the bubble / system / time subviews.
// Dependencies: SwiftUI, HibossKit SessionEvent, SessionTranscriptLayout.

import HibossKit
import SwiftUI

struct SessionTranscriptItemView: View {
    let item: SessionTranscriptItem

    var body: some View {
        switch item {
        case let .time(_, date):
            SessionTimeSeparator(date: date)
        case let .bubble(event, style):
            SessionBubbleView(event: event, style: style)
        case let .system(event):
            SessionSystemLine(event: event)
        }
    }
}

struct SessionTimeSeparator: View {
    let date: Date

    var body: some View {
        Text(label)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .accessibilityAddTraits(.isHeader)
    }

    private var label: String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

struct SessionSystemLine: View {
    let event: SessionEvent
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 2) {
            Text(shown)
                .font(bodyFont)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            if isLong {
                Button(expanded ? String(localized: "Show less") : String(localized: "Show more")) {
                    expanded.toggle()
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .buttonStyle(.plain)
                .accessibilityIdentifier("system-line-expand")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("session-system-line")
    }

    private var fullText: String { SessionTranscriptLayout.systemLabel(for: event) }
    private var isLong: Bool { fullText.count > SessionTranscriptLayout.collapseLimit }
    private var shown: String {
        expanded ? fullText : SessionTranscriptLayout.collapsed(fullText)
    }

    private var bodyFont: Font {
        event.isRawOutput ? .footnote.monospaced() : .caption
    }
}

struct SessionBubbleView: View {
    let event: SessionEvent
    let style: SessionBubbleStyle

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if style.isOutgoing { Spacer(minLength: 48) }
            bubbleColumn
            if !style.isOutgoing { Spacer(minLength: 48) }
        }
        .padding(.top, style.isFirstInGroup ? 10 : 2)
        .padding(.bottom, style.isLastInGroup ? 8 : 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier(style.isOutgoing ? "session-bubble-outgoing" : "session-bubble-incoming")
    }

    private var bubbleColumn: some View {
        VStack(alignment: style.isOutgoing ? .trailing : .leading, spacing: 2) {
            if style.showsSender {
                Text(SessionTranscriptLayout.actorLabel(for: event))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            }
            bubbleBody
        }
    }

    private var bubbleBody: some View {
        Text(event.displayBody)
            .font(.body)
            .foregroundStyle(textColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .padding(.leading, style.isOutgoing || !style.isLastInGroup ? 0 : 5)
            .padding(.trailing, style.isOutgoing && style.isLastInGroup ? 5 : 0)
            .textSelection(.enabled)
            .background(fill, in: SessionChatBubble(style: style))
    }

    private var fill: Color {
        style.isOutgoing ? Color.accentColor : Color(.systemGray5)
    }

    private var textColor: Color {
        style.isOutgoing ? Color(.systemBackground) : Color.primary
    }

    private var accessibilityText: String {
        "\(SessionTranscriptLayout.directionLabel(for: event)), \(SessionTranscriptLayout.actorLabel(for: event)), \(event.displayBody)"
    }
}

struct SessionChatBubble: Shape {
    var style: SessionBubbleStyle

    func path(in rect: CGRect) -> Path {
        let tail: CGFloat = style.isLastInGroup ? 7 : 0
        let bubble = CGRect(
            x: style.isOutgoing ? 0 : tail,
            y: 0,
            width: max(0, rect.width - tail),
            height: rect.height
        )
        var path = cornerRadii.path(in: bubble)
        if style.isLastInGroup {
            let tailRect = CGRect(
                x: style.isOutgoing ? rect.maxX - tail : 0,
                y: rect.maxY - 13,
                width: tail,
                height: 13
            )
            path.addPath(SessionBubbleTail(isOutgoing: style.isOutgoing).path(in: tailRect))
        }
        return path
    }

    private var cornerRadii: UnevenRoundedRectangle {
        let r: CGFloat = 18
        let tight: CGFloat = 4
        if style.isOutgoing {
            return UnevenRoundedRectangle(
                topLeadingRadius: r,
                bottomLeadingRadius: r,
                bottomTrailingRadius: style.isLastInGroup ? 6 : tight,
                topTrailingRadius: style.isFirstInGroup ? r : tight,
                style: .continuous
            )
        }
        return UnevenRoundedRectangle(
            topLeadingRadius: style.isFirstInGroup ? r : tight,
            bottomLeadingRadius: style.isLastInGroup ? 6 : tight,
            bottomTrailingRadius: r,
            topTrailingRadius: r,
            style: .continuous
        )
    }
}

struct SessionBubbleTail: Shape {
    var isOutgoing: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if isOutgoing {
            path.move(to: CGPoint(x: 0, y: rect.height * 0.15))
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY),
                control1: CGPoint(x: rect.maxX * 0.15, y: rect.height * 0.55),
                control2: CGPoint(x: rect.maxX * 0.85, y: rect.height * 0.75)
            )
            path.addQuadCurve(
                to: CGPoint(x: 0, y: rect.height * 0.62),
                control: CGPoint(x: rect.maxX * 0.2, y: rect.maxY)
            )
        } else {
            path.move(to: CGPoint(x: rect.maxX, y: rect.height * 0.15))
            path.addCurve(
                to: CGPoint(x: 0, y: rect.maxY),
                control1: CGPoint(x: rect.maxX * 0.85, y: rect.height * 0.55),
                control2: CGPoint(x: rect.maxX * 0.15, y: rect.height * 0.75)
            )
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.height * 0.62),
                control: CGPoint(x: rect.maxX * 0.8, y: rect.maxY)
            )
        }
        path.closeSubpath()
        return path
    }
}
