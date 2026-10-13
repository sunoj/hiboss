// Reserves media grid geometry from declared dimensions before any image is loaded.
// Exports: ProgressMediaLayout with at most two columns and bounded row heights.
// Dependencies: SwiftUI Layout and HibossKit ProgressMedia metadata.

import HibossKit
import SwiftUI

struct ProgressMediaLayout: Layout {
    let items: [ProgressMedia]
    private let spacing: CGFloat = 8

    func frames(width: CGFloat) -> [CGRect] {
        guard !items.isEmpty else { return [] }
        let columns = min(items.count, 2)
        let tileWidth = max(0, (width - CGFloat(columns - 1) * spacing) / CGFloat(columns))
        var frames: [CGRect] = []
        var y: CGFloat = 0
        for start in stride(from: 0, to: items.count, by: columns) {
            let end = min(start + columns, items.count)
            let height = items[start..<end].map { item in
                min(240, tileWidth / Self.aspectRatio(item))
            }.max() ?? 0
            for column in 0..<(end - start) {
                frames.append(CGRect(x: CGFloat(column) * (tileWidth + spacing), y: y,
                    width: tileWidth, height: height))
            }
            y += height + spacing
        }
        return frames
    }

    static func aspectRatio(_ media: ProgressMedia) -> CGFloat {
        guard let width = media.width, let height = media.height, width > 0, height > 0 else {
            return 16 / 9
        }
        return CGFloat(width) / CGFloat(height)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        return CGSize(width: width, height: frames(width: width).last?.maxY ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                       cache: inout ()) {
        for (view, frame) in zip(subviews, frames(width: bounds.width)) {
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }
}
