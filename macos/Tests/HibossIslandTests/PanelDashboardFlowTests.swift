// Exercises dashboard content, responsive packing, and live detail navigation.
// Exports: PanelDashboardFlowTests.
// Dependencies: XCTest, SwiftUI, and the shared panel dashboard components.

import AppKit
import HibossKit
import SwiftUI
import XCTest

@MainActor
final class PanelDashboardFlowTests: XCTestCase {
    func testPublishedMetricsUpdateWithoutMovingOrClosingThePanel() async throws {
        let model = PanelsModel(api: try StubPanelsService(populated: true), demoMode: false, autoload: false)
        await model.load()
        let tile = try XCTUnwrap(model.tiles.first)
        let positions = model.positions(for: 1100)
        model.open(tile.id)
        model.receive(.snapshot(PanelRelaySnapshot(
            panelID: tile.id, definitionRevision: 1, epoch: "dashboard", sequence: 1,
            task: .object(["done": .number(12)])
        )), for: tile.id)

        let content = PanelDashboardContent(fixture: tile.fixture, state: tile.store.state)
        XCTAssertEqual(content.metrics.first?.displayValue(in: tile.store.state), "12")
        XCTAssertEqual(model.selectedTile?.id, tile.id)
        XCTAssertEqual(model.positions(for: 1100), positions)
        model.closeDetail()
        XCTAssertNil(model.selectedTile)
    }

    func testMetricsFollowAuthorOrderAndProgressNeedsAnExplicitComponent() throws {
        let fixtures = try PanelFixtures.load()
        let monitor = try XCTUnwrap(fixtures.all.first { $0.name == "service-monitor.json" })
        let content = PanelDashboardContent(fixture: monitor, state: monitor.initialState)
        XCTAssertEqual(content.metrics.map(\.label), ["Monitoring duration", "Requests observed", "Error rate"])
        XCTAssertNil(content.progress)
        let transfer = try XCTUnwrap(fixtures.all.first { $0.name == "download-progress.json" })
        let progress = try XCTUnwrap(PanelDashboardContent(fixture: transfer, state: transfer.initialState).progress)
        XCTAssertEqual(progress.fraction, 0.68, accuracy: 0.001)
    }

    func testBoundChartRetainsGapsAndRefreshesFromProducerState() throws {
        let fixture = try XCTUnwrap(PanelFixtures.load().all.first { $0.name == "bound-chart.json" })
        let content = PanelDashboardContent(fixture: fixture, state: fixture.initialState)
        XCTAssertEqual(content.series?.values, [12, nil, 18])
        let updated = PanelDashboardContent(fixture: fixture, state: .object([
            "task": .object(["series": .array([.number(30), .null, .number(42)])])
        ]))
        XCTAssertEqual(updated.series?.values, [30, nil, 42])
    }

    func testPhoneFitsTwoCompactTilesAndWideChartsUseTheWholeRow() {
        let panels = [
            PanelLayoutPanel(id: "one", size: .compact, order: 0, isPinned: false),
            PanelLayoutPanel(id: "two", size: .compact, order: 1, isPinned: false),
            PanelLayoutPanel(id: "chart", size: .wide, order: 2, isPinned: false),
        ]
        let positions = PanelWallLayout.arrange(panels, width: 370)
        XCTAssertEqual(positions[0].frame.minY, positions[1].frame.minY)
        XCTAssertEqual(positions[1].frame.maxX, 370, accuracy: 0.01)
        XCTAssertEqual(positions[2].frame.width, 370, accuracy: 0.01)
        for width: CGFloat in [280, 370, 520, 760, 1100, 1600] {
            let layout = PanelWallLayout.arrange(panels, width: width)
            for tile in layout { XCTAssertLessThanOrEqual(tile.frame.maxX, width + 0.01) }
            for pair in zip(layout, layout.dropFirst()) {
                XCTAssertFalse(pair.0.frame.intersects(pair.1.frame))
            }
        }
    }

    func testDashboardRendersInBothAppearances() throws {
        let fixtures = try PanelFixtures.load().all
        for scheme in [ColorScheme.dark, .light] {
            let tiles = fixtures.enumerated().map { index, fixture in
                PanelTile(id: fixture.name, fixture: fixture, store: PanelStore(fixture: fixture),
                          producer: nil, agentID: "preview", agentName: "Preview agent", sessionLabel: nil,
                          definitionRevision: nil, order: index)
            }
            let renderer = ImageRenderer(content: dashboard(tiles, scheme: scheme))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage)
            XCTAssertGreaterThan(image.size.width, 1000)
            if let directory = ProcessInfo.processInfo.environment["HIBOSS_PANEL_SNAPSHOTS"],
               let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("dashboard-\(scheme).png"))
            }
        }
    }

    private func dashboard(_ tiles: [PanelTile], scheme: ColorScheme) -> some View {
        let positions = PanelWallLayout.arrange(tiles.map {
            PanelLayoutPanel(id: $0.id, size: $0.fixture.spec.tileSize, order: $0.order, isPinned: false)
        }, width: 1100)
        return VStack(alignment: .leading, spacing: 20) {
            Text("Panels").font(.largeTitle.bold())
            Text("Sample data · 8 panels").foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
                ForEach(Array(zip(tiles, positions)), id: \.0.id) { tile, position in
                    PanelDashboardCard(tile: tile, freshness: .live) {}
                        .frame(width: position.frame.width, height: position.frame.height)
                        .offset(x: position.frame.minX, y: position.frame.minY)
                }
            }
            .frame(width: 1100, height: positions.map { $0.frame.maxY }.max() ?? 0, alignment: .topLeading)
        }
        .padding(24)
        .background(scheme == .dark ? Color.black : Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, scheme)
    }
}
