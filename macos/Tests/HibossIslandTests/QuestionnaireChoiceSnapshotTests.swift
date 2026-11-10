// Renders questionnaire Select/MultiSelect rows offscreen and reads back the question and trade-offs.
// Exports QuestionnaireChoiceSnapshotTests; HIBOSS_SNAPSHOT_DIR retains light and dark PNG evidence.
// Dependencies: AppKit, SwiftUI ImageRenderer, Vision and HibossKit.

import AppKit
@testable import HibossKit
import SwiftUI
import Vision
import XCTest

@MainActor
final class QuestionnaireChoiceSnapshotTests: XCTestCase {
    func testChoiceRowsShowTheQuestionAndEveryOptionDescription() throws {
        _ = NSApplication.shared
        let fixture = try PanelFixture(name: "choices.json", data: Data(Self.formJSON.utf8))
        let store = PanelStore(fixture: fixture)
        let view = AnyView(PanelRenderer(spec: fixture.spec, store: store, webModel: PanelWebModel()))
        for scheme in [ColorScheme.light, .dark] {
            let image = try render(view, scheme: scheme)
            try write(image, name: "macos-questionnaire-choices-\(scheme)")
            let text = try recognizedText(image)
            for expected in ["Which rollout should ship first", "Every user at once", "Three batches, one day apart",
                             "A crash reaches everyone", "Evidence to prioritize", "Measured on our own workload"] {
                XCTAssertTrue(text.contains(expected), "missing \(expected) in \(scheme): \(text)")
            }
        }
    }

    private func recognizedText(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }

    private func render(_ view: AnyView, scheme: ColorScheme) throws -> CGImage {
        let appearance = try XCTUnwrap(NSAppearance(named: scheme == .light ? .aqua : .darkAqua))
        var result: CGImage?
        appearance.performAsCurrentDrawingAppearance {
            let renderer = ImageRenderer(content: view.frame(width: 520)
                .fixedSize(horizontal: false, vertical: true).padding(18)
                .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, scheme))
            renderer.scale = 2
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

    private static let formJSON = #"""
    {"title":"Rollout intake","defaults":{"rollout":"batches","evidence":["benchmarks"]},
     "formSpec":{"root":"form","elements":{
      "form":{"type":"Stack","props":{"direction":"vertical"},"children":["rollout","evidence","notify"]},
      "rollout":{"type":"Select","props":{"label":"Which rollout should ship first?",
       "value":{"$bindState":"/form/rollout"},"options":[
        {"id":"all","label":"Every user at once","description":"Fastest. A crash reaches everyone."},
        {"id":"batches","label":"Three batches, one day apart","description":"Two days slower; a crash reaches a few."}]},
       "children":[]},
      "evidence":{"type":"MultiSelect","props":{"label":"Evidence to prioritize",
       "value":{"$bindState":"/form/evidence"},"options":[
        {"id":"literature","label":"Literature review","description":"Broad and fast."},
        {"id":"benchmarks","label":"Benchmarks","description":"Measured on our own workload."}]},
       "children":[]},
      "notify":{"type":"Toggle","props":{"label":"Notify the team","description":"Posts once in the release channel.",
       "value":{"$bindState":"/form/notify"}},"children":[]}}}}
    """#
}
