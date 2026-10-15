// Native choice buttons for a pending decision, shared by the Home card and message detail.
// Exports: DecisionOptions and DecisionOptionFlow. Today wraps choices to the available width;
// detail and thread choices retain their shared-height two-option row or vertical stack.
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
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        if metadata?.optionDescriptions.isEmpty == false {
            VStack(spacing: 8) {
                ForEach(options, id: \.self) { button($0, alignment: .leading) }
            }
        } else if wrapsToFit {
            DecisionOptionFlow(layoutDirection: layoutDirection) {
                ForEach(options, id: \.self) { button($0, alignment: .center) }
            }
        } else if options.count == 2 && !fullWidth {
            // The row takes its tallest label's height and both buttons fill it, so a label that
            // wraps at large text never leaves its neighbour shorter.
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { button($0, alignment: .center) }
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: 8) {
                ForEach(options, id: \.self) { button($0, alignment: .leading) }
            }
        }
    }

    @ViewBuilder
    private func button(_ option: String, alignment: Alignment) -> some View {
        let isDefault = timing.isAutoDefault(option)
        let control = Button { onChoose(option) } label: { label(option, alignment: alignment) }
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier(option)
            .accessibilityLabel(Text(verbatim: [option, metadata?.optionDescription(for: option)]
                .compactMap { $0 }.joined(separator: ", ")))
            .accessibilityValue(isDefault ? Text("Default") : Text(verbatim: ""))
        .accessibilityHint(isDefault ? Text("Selected automatically when time runs out") : Text(verbatim: ""))
        Group {
            if option == options.first {
                control.prominentAction().tint(Theme.primaryAction)
            } else {
                control.buttonStyle(.bordered).buttonBorderShape(.capsule)
                    .tint(Theme.surface).foregroundStyle(Theme.ink)
                    .overlay {
                        Capsule().strokeBorder(Theme.line, lineWidth: 1).allowsHitTesting(false)
                    }
            }
        }
        .disabled(submitting != nil && locksControls)
    }

    private func label(_ option: String, alignment: Alignment) -> some View {
        VStack(alignment: alignment == .leading ? .leading : .center, spacing: 3) {
            Text(verbatim: option)
            if let description = metadata?.optionDescription(for: option) {
                Text(verbatim: description).font(.caption)
                    .foregroundStyle(option == options.first ? Theme.onAccent.opacity(0.85) : Theme.ink2)
            }
        }
            .multilineTextAlignment(alignment == .leading ? .leading : .center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: alignment)
            .padding(.horizontal, 20)
            .overlay(alignment: .trailing) {
                if submitting == option.trimmingCharacters(in: .whitespacesAndNewlines) {
                    DelayedProgressView(tint: option == options.first ? Theme.onAccent : Theme.ink)
                }
            }
        .frame(minWidth: 44, minHeight: 44)
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

    static func frames(sizes: [CGSize], width: CGFloat, spacing: CGFloat = 8) -> [CGRect] {
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
