// Native tile-wall layout from panel identity, width hints, and intrinsic card sizes.
// Exports: PanelTileSize, PanelLayoutPanel, PanelTilePosition, and PanelWallLayout.
// Dependencies: CoreGraphics, SwiftUI Layout, and PanelSpec.

import CoreGraphics
import SwiftUI

public enum PanelTileSize: Equatable, Sendable {
    case compact
    case wide

    var isWide: Bool { self != .compact }
}

public struct PanelTileSizeLayoutValueKey: LayoutValueKey {
    public static let defaultValue: PanelTileSize = .compact
}

public struct PanelLayoutPanel: Equatable, Sendable {
    public let id: String
    public let size: PanelTileSize
    public let order: Int
    public let isPinned: Bool
    public let height: CGFloat

    public init(id: String, size: PanelTileSize, order: Int, isPinned: Bool, height: CGFloat = 0) {
        self.id = id
        self.size = size
        self.order = order
        self.isPinned = isPinned
        self.height = height
    }
}

public struct PanelTilePosition: Equatable, Identifiable, Sendable {
    public let id: String
    public let frame: CGRect
}

public struct PanelWallLayout: Layout {
    public static let gap: CGFloat = 16

    public init() {}

    public func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? 320
        return CGSize(width: width, height: placements(for: subviews, width: width).map { $0.frame.maxY }.max() ?? 0)
    }

    public func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        for placement in placements(for: subviews, width: bounds.width) {
            subviews[placement.index].place(
                at: CGPoint(x: bounds.minX + placement.frame.minX, y: bounds.minY + placement.frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: placement.frame.width, height: placement.frame.height)
            )
        }
    }

    public static func arrange(_ panels: [PanelLayoutPanel], width: CGFloat) -> [PanelTilePosition] {
        let availableWidth = max(1, width)
        let minimumColumn: CGFloat = availableWidth < 488 ? 160 : 236
        let columns = max(1, Int((availableWidth + gap) / (minimumColumn + gap)))
        let columnWidth = (availableWidth - CGFloat(columns - 1) * gap) / CGFloat(columns)
        let ordered = panels.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.id < $1.id
        }
        var cursor = CGPoint.zero
        var rowHeight: CGFloat = 0
        var positions: [PanelTilePosition] = []

        for panel in ordered {
            let span = panel.size.isWide ? min(2, columns) : 1
            let tileWidth = columnWidth * CGFloat(span) + gap * CGFloat(span - 1)
            if cursor.x > 0, cursor.x + tileWidth > availableWidth + 0.01 {
                cursor = CGPoint(x: 0, y: cursor.y + rowHeight + gap)
                rowHeight = 0
            }
            positions.append(PanelTilePosition(id: panel.id, frame: CGRect(origin: cursor, size: CGSize(width: tileWidth, height: panel.height))))
            cursor.x += tileWidth + gap
            rowHeight = max(rowHeight, panel.height)
        }
        return positions
    }

    private struct Placement {
        let index: Int
        let frame: CGRect
    }

    private func placements(for subviews: Subviews, width: CGFloat) -> [Placement] {
        let availableWidth = max(1, width)
        let minimumColumn: CGFloat = availableWidth < 488 ? 160 : 236
        let columns = max(1, Int((availableWidth + Self.gap) / (minimumColumn + Self.gap)))
        let columnWidth = (availableWidth - CGFloat(columns - 1) * Self.gap) / CGFloat(columns)
        var column = 0
        var rowY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var result: [Placement] = []

        for index in subviews.indices {
            let span = subviews[index][PanelTileSizeLayoutValueKey.self].isWide ? min(2, columns) : 1
            if column > 0, column + span > columns {
                rowY += rowHeight + Self.gap
                column = 0
                rowHeight = 0
            }
            let tileWidth = columnWidth * CGFloat(span) + Self.gap * CGFloat(span - 1)
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: tileWidth, height: nil))
            result.append(Placement(
                index: index,
                frame: CGRect(x: columnWidth * CGFloat(column) + Self.gap * CGFloat(column), y: rowY,
                              width: tileWidth, height: size.height)
            ))
            column += span
            rowHeight = max(rowHeight, size.height)
            if column == columns {
                rowY += rowHeight + Self.gap
                column = 0
                rowHeight = 0
            }
        }
        return result
    }
}

extension PanelSpec {
    public var tileSize: PanelTileSize {
        specContainsSeries ? .wide : .compact
    }

    private var specContainsSeries: Bool {
        elements.values.contains { element in
            element.type == "Table" || element.type == "LineChart" || element.type == "BarChart"
        }
    }

}
