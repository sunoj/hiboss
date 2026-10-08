// Measures rendered budget metrics at the iPhone 15 Pro's card width.
// Exports PanelMetricRenderTests; OCR checks complete values, units and labels.
// Dependencies: SwiftUI ImageRenderer, Vision, and shared native panel consumers.

@testable import HibossKit
@testable import HiBoss
import SwiftUI
import Vision
import XCTest

@MainActor
final class PanelMetricRenderTests: XCTestCase {
    func testDemoLoadsBudgetPanelBeforeTimeout() async throws {
        let panels = PanelsModel(api: DemoMetricPanelAPI(), demoMode: false, autoload: false)
        panels.clockTask?.cancel()
        await panels.load()
        XCTAssertEqual(panels.loadState, .loaded)
        XCTAssertEqual(panels.tiles.count, 1)
    }

    func testWallAndDetailKeepEachNumberAndUnitOnOneLine() throws {
        let fixture = try PanelMetricExample.load()
        let store = PanelStore(fixture: fixture)
        let tile = PanelTile(id: "metric", fixture: fixture, store: store, producer: nil,
                             agentID: nil, agentName: nil, sessionLabel: nil,
                             definitionRevision: nil, order: 0)
        for size in [DynamicTypeSize.large, .accessibility2] {
            let views = [
                AnyView(PanelTilePreview(tile: tile)),
                AnyView(PanelRenderer(spec: fixture.spec, store: store, webModel: PanelWebModel(),
                                      elementID: "metrics")),
            ]
            for (index, view) in views.enumerated() {
                let lines = try recognize(view.environment(\.dynamicTypeSize, size), width: 325,
                                          name: "metric-\(index)-\(size)")
                for value in ["8,438,950", "4,554,994", "1,068,560"] {
                    XCTAssertTrue(lines.contains { $0.contains(value + " ") }, "\(value): \(lines)")
                }
            }
        }
    }

    func testMetricLabelsUseTwoLinesBeforeTruncating() throws {
        let fixture = try PanelMetricExample.load()
        let store = PanelStore(fixture: fixture)
        let tile = PanelTile(id: "metric", fixture: fixture, store: store, producer: nil,
                             agentID: nil, agentName: nil, sessionLabel: nil,
                             definitionRevision: nil, order: 0)
        let wall = try recognize(PanelTilePreview(tile: tile), width: 325, name: "metric-wall-labels")
        for label in ["Construction P50", "House P50 (target)", "Systems P50"] {
            XCTAssertTrue(wall.joined(separator: " ").contains(label), "\(wall)")
        }
        for (id, label) in [("construction", "Construction P50"), ("house", "House P50 (target)")] {
            let view = PanelRenderer(spec: fixture.spec, store: PanelStore(fixture: fixture),
                                     webModel: PanelWebModel(), elementID: id)
            let lines = try recognize(view, width: 110, name: "metric-label-\(id)")
            XCTAssertTrue(lines.joined(separator: " ").contains(label), "\(lines)")
            XCTAssertFalse(lines.contains { $0.contains("…") })
        }
    }

    private func recognize<V: View>(_ view: V, width: CGFloat, name: String) throws -> [String] {
        let renderer = ImageRenderer(content: view.frame(width: width)
            .fixedSize(horizontal: false, vertical: true).padding(12).background(.background))
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.uiImage)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }
}
