// A form ask on the Today card: the v2 control replaces the choice buttons, in light and dark.
// Exports: AskFormWindowTests; HIBOSS_TODAY_SCREENSHOTS=<dir> writes light and dark captures.
// Dependencies: AppKit, SwiftUI, Vision, HibossKit, the production TodayDecisionCard and window fixtures.

import AppKit
import HibossKit
import SwiftUI
import Vision
import XCTest
@testable import HibossIsland

@MainActor
final class AskFormWindowTests: XCTestCase {
    private static let ranked = #"{"catalogVersion":2,"input":{"type":"RankedChoice","props":{"label":"Order the follow-ups for next week","value":{"$bindState":"/form/answer"},"options":[{"id":"sync","label":"Fix the flaky sync test"},{"id":"settings","label":"Split the settings screen"},{"id":"flag","label":"Rename the export flag"}]}}}"#
    private static let review = #"{"catalogVersion":2,"input":{"type":"ItemReview","props":{"label":"Pre-release checklist","value":{"$bindState":"/form/answer"},"items":[{"id":"changelog","label":"Changelog read end to end"},{"id":"rollback","label":"Rollback steps tested"}],"verdicts":[{"id":"ok","label":"Confirmed"},{"id":"no","label":"Cannot confirm","requiresNote":true}]}}}"#

    func testFormAskReplacesChoicesWithTheFormInBothAppearances() async throws {
        let action = AskFormAnswerAction { _, _, _ in nil }
        for (name, json, expected) in [("ranked", Self.ranked, "Rename the export flag"),
                                       ("review", Self.review, "Cannot confirm")] {
            for scheme in [ColorScheme.light, .dark] {
                let item = try formItem(id: "form-\(name)", json: json)
                let card = TodayDecisionCard(item: item, now: .now, isSubmitting: false, error: nil,
                    onSelect: {}, onChoose: { _ in XCTFail("A form ask must not send a choice") },
                    reply: AttentionReplyState())
                    .padding(20).frame(width: 640)
                    .environment(\.askFormAnswer, action).environment(\.colorScheme, scheme)
                let window = try PerfSurveyFixtures.window(card.background(Color(nsColor: .windowBackgroundColor)))
                defer { PerfSurveyFixtures.close(window) }
                window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
                window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
                window.orderFrontRegardless()
                try await BoxWindowCaptureSupport.settle(window)
                let words = try recognizedText(window)
                XCTAssertTrue(words.contains(expected), "\(name): \(words)")
                XCTAssertTrue(words.contains("Submit answer"), "\(name): \(words)")
                XCTAssertFalse(words.contains("Keep this order"), "An ask submits the shown order: \(words)")
                if let directory = ProcessInfo.processInfo.environment["HIBOSS_TODAY_SCREENSHOTS"] {
                    try BoxWindowCaptureSupport.capture(window, directory: directory,
                        name: "ask-form-\(name)-\(scheme == .light ? "light" : "dark")")
                }
            }
        }
    }

    private func recognizedText(_ window: NSWindow) throws -> String {
        let view = try XCTUnwrap(window.contentView)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }

    private func formItem(id: String, json: String) throws -> AttentionItem {
        let form = try JSONDecoder().decode(PanelValue.self, from: Data(json.utf8))
        let base = AttentionTestSupport.ask(id: MessageID(rawValue: id), body: "Plan next week", options: [])
        let message = HistoryMessage(id: base.id, body: base.body, agentName: base.agentName,
            direction: base.direction, status: base.status, priority: base.priority, mode: "blocking",
            metadata: MessageMetadata(options: [], formValue: form), createdAt: base.createdAt,
            sessionLabel: base.sessionLabel)
        return AttentionItem(message: message, group: .priority)
    }
}
