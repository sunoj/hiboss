// Renders shared budget metrics in narrow and wide macOS panel consumers.
// Exports PanelMetricSnapshotTests; HIBOSS_SNAPSHOT_DIR retains PNG evidence.
// Dependencies: AppKit, SwiftUI ImageRenderer, Vision and HibossKit.

import AppKit
@testable import HibossKit
import SwiftUI
import Vision
import XCTest

@MainActor
final class PanelMetricSnapshotTests: XCTestCase {
    func testWallAndDetailKeepCompleteBudgetValues() throws {
        _ = NSApplication.shared
        let fixture = try PanelMetricExample.load()
        let store = PanelStore(fixture: fixture)
        let tile = PanelTile(id: "metric", fixture: fixture, store: store, producer: nil,
                             agentID: nil, agentName: nil, sessionLabel: nil,
                             definitionRevision: nil, order: 0)
        let views = [AnyView(PanelTilePreview(tile: tile)),
                     AnyView(PanelRenderer(spec: fixture.spec, store: store, webModel: PanelWebModel(),
                                           elementID: "metrics"))]
        for (index, view) in views.enumerated() {
            for width: CGFloat in [325, 1_000] {
                for scheme in [ColorScheme.light, .dark] {
                    let image = try render(view, width: width, scheme: scheme)
                    try write(image, name: "macos-metrics-\(index)-\(Int(width))-\(scheme)")
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.recognitionLanguages = ["en-US"]
                    request.usesLanguageCorrection = false
                    try VNImageRequestHandler(cgImage: image).perform([request])
                    let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                    for value in ["8,438,950", "4,554,994", "1,068,560"] {
                        XCTAssertTrue(lines.contains { $0.contains(value + " ") }, "\(lines)")
                    }
                }
            }
        }
    }

    private func render(_ view: AnyView, width: CGFloat, scheme: ColorScheme) throws -> CGImage {
        let appearance = try XCTUnwrap(NSAppearance(named: scheme == .light ? .aqua : .darkAqua))
        var result: CGImage?
        appearance.performAsCurrentDrawingAppearance {
            let renderer = ImageRenderer(content: view.frame(width: width)
                .fixedSize(horizontal: false, vertical: true).padding(18)
                .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, scheme))
            renderer.scale = 3
            result = renderer.cgImage
        }
        return try XCTUnwrap(result)
    }

    private func write(_ image: CGImage, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["HIBOSS_SNAPSHOT_DIR"] else { return }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try png.write(to: url.appendingPathComponent("\(name).png"))
    }
}
