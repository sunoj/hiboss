// Native metric presentation and width-driven column reflow.
// Exports internal PanelMetricView and PanelMetricLayout for wall and detail rendering.
// Dependencies: SwiftUI semantic typography and Layout measurement.

import SwiftUI

struct PanelMetricView: View {
    let label: String
    let value: String
    let unit: String?
    var labelFont: Font = .callout
    var valueFont: Font = .title2.bold()
    var unitFont: Font = .callout
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: label).font(labelFont).foregroundStyle(.secondary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            valueText
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var valueText: Text {
        Text(verbatim: value).font(valueFont).foregroundColor(valueColor)
            + Text(verbatim: unit.map { " \($0)" } ?? "").font(unitFont).foregroundColor(.secondary)
    }
}

struct PanelMetricLayout: Layout {
    let columns: Int
    let gap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = usableWidth(proposal.width, subviews: subviews)
        let frames = frames(width: width, subviews: subviews)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, frame) in frames(width: bounds.width, subviews: subviews).enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                                 anchor: .topLeading,
                                 proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    private func usableWidth(_ proposed: CGFloat?, subviews: Subviews) -> CGFloat {
        if let proposed, proposed.isFinite { return max(1, proposed) }
        let count = max(1, min(columns, subviews.count))
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        return ideal * CGFloat(count) + gap * CGFloat(count - 1)
    }

    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        var count = max(1, min(columns, subviews.count))
        while count > 1 && ideal * CGFloat(count) + gap * CGFloat(count - 1) > width {
            count -= 1
        }
        let cellWidth = max(1, (width - gap * CGFloat(count - 1)) / CGFloat(count))
        var result: [CGRect] = []
        var y: CGFloat = 0
        for start in stride(from: 0, to: subviews.count, by: count) {
            let end = min(start + count, subviews.count)
            let heights = (start..<end).map {
                subviews[$0].sizeThatFits(ProposedViewSize(width: cellWidth, height: nil)).height
            }
            for index in start..<end {
                result.append(CGRect(x: CGFloat(index - start) * (cellWidth + gap), y: y,
                                     width: cellWidth, height: heights[index - start]))
            }
            y += (heights.max() ?? 0) + gap
        }
        return result
    }
}
