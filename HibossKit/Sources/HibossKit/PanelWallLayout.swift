// Pure append-only tile-wall packing from panel identity, size, width, and pins.
// Exports: PanelTileSize, PanelLayoutPanel, PanelTilePosition, and PanelWallLayout.
// Dependencies: CoreGraphics and PanelSpec for content-derived tile sizing.

import CoreGraphics

public enum PanelTileSize: Equatable, Sendable {
    case compact
    case wide

    public var dimensions: CGSize {
        switch self {
        case .compact: CGSize(width: 236, height: 320)
        case .wide: CGSize(width: 488, height: 320)
        }
    }
}

public struct PanelLayoutPanel: Equatable, Sendable {
    public let id: String
    public let size: PanelTileSize
    public let order: Int
    public let isPinned: Bool

    public init(id: String, size: PanelTileSize, order: Int, isPinned: Bool) {
        self.id = id
        self.size = size
        self.order = order
        self.isPinned = isPinned
    }
}

public struct PanelTilePosition: Equatable, Identifiable, Sendable {
    public let id: String
    public let frame: CGRect
}

public enum PanelWallLayout {
    public static let gap: CGFloat = 16

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
            let dimensions = panel.size.dimensions
            let span = panel.size == .wide ? min(2, columns) : 1
            let tileWidth = columnWidth * CGFloat(span) + gap * CGFloat(span - 1)
            if cursor.x > 0, cursor.x + tileWidth > availableWidth + 0.01 {
                cursor = CGPoint(x: 0, y: cursor.y + rowHeight + gap)
                rowHeight = 0
            }
            positions.append(PanelTilePosition(id: panel.id, frame: CGRect(origin: cursor, size: CGSize(width: tileWidth, height: dimensions.height))))
            cursor.x += tileWidth + gap
            rowHeight = max(rowHeight, dimensions.height)
        }
        return positions
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
