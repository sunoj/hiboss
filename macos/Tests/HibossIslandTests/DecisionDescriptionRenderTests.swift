// Verifies option explanations on open and settled desktop decisions in both appearances.
// Dependencies: SwiftUI ImageRenderer, AppKit, Vision OCR, and the production decision views.

import AppKit
import HibossKit
import SwiftUI
import Vision
import XCTest
@testable import HibossIsland

@MainActor
final class DecisionDescriptionRenderTests: XCTestCase {
    func testTradeoffsRemainReadableBeforeAndAfterChoosing() throws {
        let message = HistoryMessage(id: "rollout", body: "Choose a rollout", direction: "agent_to_boss",
            status: "delivered", priority: "normal", metadata: MessageMetadata(options: ["Ship", "Pilot"],
                optionDescriptions: [OptionDescription(label: "Ship", text: "Everyone gets the release"),
                                     OptionDescription(label: "Pilot", text: "Start with one team")]),
            createdAt: "2026-11-01T00:00:00Z")
        let item = AttentionItem(message: message, group: .priority)
        let thread = MessageThread(message: message, replies: [])
        for scheme in [ColorScheme.light, .dark] {
            let choices = DecisionChoices(item: item, onChoose: { _ in })
            let labels = try renderedText(choices, scheme: scheme, name: "choices")
            XCTAssertTrue(labels.contains("Everyone gets the release"), labels)
            XCTAssertTrue(labels.contains("Start with one team"), labels)
            let history = HistoryDecisionBlock(thread: thread, reply: AttentionReplyState(),
                onChoose: { _ in nil })
            let historical = try renderedText(history, scheme: scheme, name: "history")
            XCTAssertTrue(historical.contains("Everyone gets the release"), historical)
            let banner = ResolvedBanner(thread: thread, outcome: .chosen(option: "Pilot", source: nil))
            let result = try renderedText(banner, scheme: scheme, name: "answer")
            XCTAssertTrue(result.contains("Start with one team"), result)
            XCTAssertFalse(result.contains("Everyone gets the release"), result)
        }
    }

    private func renderedText(_ view: some View, scheme: ColorScheme, name: String) throws -> String {
        let renderer = ImageRenderer(content: view.frame(width: 320)
            .fixedSize(horizontal: false, vertical: true)
            .padding().background(.background).environment(\.colorScheme, scheme))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage)
        if let directory = ProcessInfo.processInfo.environment["HIBOSS_SNAPSHOT_DIR"] {
            let bitmap = NSBitmapImageRep(cgImage: image)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let folder = URL(fileURLWithPath: directory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: folder.appendingPathComponent("decision-\(name)-\(scheme).png"))
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }
}
