// Bounds metric-update CPU in the production Panels wall with real AppKit windows.
// Exports: PanelMetricPerformanceTests; optional PNG evidence via HIBOSS_PANEL_SNAPSHOTS.
// Dependencies: PerfSurvey fixtures and CPU clocks, AppKit, SwiftUI, and HibossKit.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class PanelMetricPerformanceTests: XCTestCase {
    func testMetricUpdateDoesNotDriveAnAnimationLoop() async throws {
        for count in [1, 50] {
            let model = PanelsModel(api: try await PerfSurveyPanelsAPI(count: count),
                                    demoMode: false, autoload: false)
            await model.load()
            XCTAssertEqual(model.tiles.count, count)
            let window = try PerfSurveyFixtures.window(PerfSurveyPanelSurface(model: model))
            defer { PerfSurveyFixtures.close(window) }
            try await Task.sleep(for: .seconds(1))
            let tile = try XCTUnwrap(model.tiles.first)
            let milliseconds = try await PerfSurveyMetrics.action(window) {
                tile.store.setNumber(4, at: "/task/done")
            }
            let content = PanelDashboardContent(fixture: tile.fixture, state: tile.store.state)
            XCTAssertEqual(content.metrics.first?.displayValue(in: tile.store.state), "4")
            // The numeric transition previously consumed about 300 ms, even for one tile.
            XCTAssertLessThan(milliseconds, 50, "\(count) tiles: \(milliseconds) ms main-thread CPU")
            try await capture(window, count: count)
        }
    }

    private func capture(_ window: NSWindow, count: Int) async throws {
        guard let directory = ProcessInfo.processInfo.environment["HIBOSS_PANEL_SNAPSHOTS"] else { return }
        let root = try XCTUnwrap(window.contentView)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            window.appearance = try XCTUnwrap(NSAppearance(named: appearance))
            try await Task.sleep(for: .milliseconds(300))
            root.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            let bitmap = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
            root.cacheDisplay(in: root.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: directory)
                .appendingPathComponent("panels-\(count)-\(name).png"))
        }
    }
}
