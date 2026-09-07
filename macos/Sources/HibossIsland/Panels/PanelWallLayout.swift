// Pure append-only tile-wall packing from panel identity, size, width, and pins.
// Exports: PanelTileSize, PanelLayoutPanel, PanelTilePosition, and PanelWallLayout.
// Dependencies: CoreGraphics and PanelSpec for content-derived tile sizing.

import CoreGraphics

enum PanelTileSize: Equatable, Sendable {
    case compact
    case wide

    var dimensions: CGSize {
        switch self {
        case .compact: CGSize(width: 236, height: 176)
        case .wide: CGSize(width: 488, height: 176)
        }
    }
}

struct PanelLayoutPanel: Equatable, Sendable {
    let id: String
    let size: PanelTileSize
    let order: Int
    let isPinned: Bool
}

struct PanelTilePosition: Equatable, Identifiable, Sendable {
    let id: String
    let frame: CGRect
}

enum PanelWallLayout {
    static let gap: CGFloat = 16

    static func arrange(_ panels: [PanelLayoutPanel], width: CGFloat) -> [PanelTilePosition] {
        let availableWidth = max(1, width)
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
            let tileWidth = min(dimensions.width, availableWidth)
            if cursor.x > 0, cursor.x + tileWidth > availableWidth {
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
    var tileSize: PanelTileSize {
        specContainsSeries ? .wide : .compact
    }

    private var specContainsSeries: Bool {
        elements.values.contains { element in
            element.type == "Table" || element.type == "LineChart" || element.type == "BarChart"
        }
    }
}
