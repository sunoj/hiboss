// Native choice buttons for a pending decision, shared by the Home card and message detail.
// Exports: DecisionOptions and the flow measurement helper used by projection tests.
// Today, detail and thread choices share full-width, vertically stacked actions.
// Dependencies: SwiftUI, DecisionTiming (which option is the live timeout default).

import HibossKit
import SwiftUI

struct DecisionOptions: View {
    let options: [String]
    var metadata: MessageMetadata? = nil
    let timing: DecisionTiming
    var submitting: String?
    var locksControls = true
    var wrapsToFit = false
    var fullWidth = false
    let onChoose: (String) -> Void
    var body: some View {
        VStack(spacing: Space.xs) {
            ForEach(options, id: \.self) { button($0, alignment: .leading) }
        }
    }

    @ViewBuilder
    private func button(_ option: String, alignment: Alignment) -> some View {
        let isDefault = timing.isAutoDefault(option)
        let control = Button { onChoose(option) } label: { label(option, alignment: alignment) }
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier(option)
            .accessibilityLabel(Text(verbatim: metadata?.optionDescription(for: option)
                .map { "\(option). \($0)" } ?? option))
            .accessibilityValue(isDefault ? Text("Default") : Text(verbatim: ""))
        .accessibilityHint(isDefault ? Text("Selected automatically when time runs out") : Text(verbatim: ""))
        control.hbButton(option == options.first ? .primary : .secondary)
        .disabled(submitting != nil && locksControls)
    }

    private func label(_ option: String, alignment: Alignment) -> some View {
        VStack(alignment: alignment == .leading ? .leading : .center, spacing: Space.xxs) {
            Text(verbatim: option)
            if let description = metadata?.optionDescription(for: option) {
                Text(verbatim: description).font(.caption)
                    .foregroundStyle(option == options.first ? Theme.onAccent.opacity(0.85) : Theme.ink2)
            }
        }
            .multilineTextAlignment(alignment == .leading ? .leading : .center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: alignment)
            .overlay(alignment: .trailing) {
                if submitting == option.trimmingCharacters(in: .whitespacesAndNewlines) {
                    DelayedProgressView(tint: option == options.first ? Theme.onAccent : Theme.ink)
                }
            }
        .frame(minWidth: ControlMetric.minTap, minHeight: ControlMetric.minTap)
        .frame(maxHeight: alignment == .center ? .infinity : nil)
    }
}

/// Native buttons retain their ideal width until a row runs out of room.
struct DecisionOptionFlow: Layout {
    var layoutDirection: LayoutDirection = .leftToRight

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = frames(proposal: proposal, subviews: subviews)
        return CGSize(width: proposal.width ?? frames.map(\.maxX).max() ?? 0,
                      height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = frames(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews)
        for (subview, frame) in zip(subviews, frames) {
            let x = layoutDirection == .rightToLeft ? bounds.width - frame.maxX : frame.minX
            subview.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + frame.minY),
                          anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }

    private func frames(proposal: ProposedViewSize, subviews: Subviews) -> [CGRect] {
        let width = proposal.width ?? .infinity
        let sizes = subviews.map { subview in
            let ideal = subview.sizeThatFits(.unspecified)
            return subview.sizeThatFits(ProposedViewSize(width: min(ideal.width, width), height: nil))
        }
        return Self.frames(sizes: sizes, width: width)
    }

    static func frames(sizes: [CGSize], width: CGFloat, spacing: CGFloat = Space.xs) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var rowStart = 0
        for size in sizes {
            let itemWidth = min(size.width, width)
            if x > 0 && x + itemWidth > width {
                for index in rowStart..<frames.count { frames[index].size.height = rowHeight }
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
                rowStart = frames.count
            }
            frames.append(CGRect(x: x, y: y, width: itemWidth, height: size.height))
            rowHeight = max(rowHeight, size.height)
            x += itemWidth + spacing
        }
        for index in rowStart..<frames.count { frames[index].size.height = rowHeight }
        return frames
    }
}

// Secondary plain text shared by resolved options and image comparisons.
// Dependencies: SwiftUI semantic caption and Theme secondary label colour.
struct OptionDescriptionText: View {
    let text: String?

    var body: some View {
        if let text {
            Text(verbatim: text).font(.caption).foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
