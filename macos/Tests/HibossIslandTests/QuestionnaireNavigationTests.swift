// Exercises a long questionnaire through the Mac editor, including its draft and review page.
// Dependencies: SwiftUI, AppKit, Vision, the shared research intake and a local questionnaire service.

import AppKit
@testable import HibossKit
import SwiftUI
import Vision
import XCTest

@MainActor
final class QuestionnaireNavigationTests: XCTestCase {
    func testAnswerReviewAndReopenDraftInBothAppearances() async throws {
        let api = try StableReadAPI()
        for scheme in [ColorScheme.light, .dark] {
            let record = try intake()
            let key = "hiboss.questionnaire.\(api.questionnaireScope).boss.\(record.id).1"
            defer { UserDefaults.standard.removeObject(forKey: key) }
            let window = try await open(record, api, scheme)
            defer { window.close() }
            try await verifySteps(in: window, scheme: scheme)
            let reopened = try await open(record, api, scheme)
            defer { reopened.close() }
            let labels = try await observations(in: reopened).map(\.text)
            XCTAssertTrue(labels.contains("Review your answers"), "\(labels)")
            XCTAssertTrue(labels.contains("Benchmarks"), "\(labels)")
        }
    }

    func testShortFormSubmitsInlineAndViewerCanReviewWithoutSubmitting() async throws {
        let api = try StableReadAPI()
        let short = try await open(intake(single: true), api, .light)
        defer { short.close() }
        let inline = try await observations(in: short).map(\.text)
        XCTAssertTrue(inline.contains("Submit answers"), "\(inline)")
        XCTAssertFalse(inline.contains("Next"))
        let viewer = try await open(intake(), api, .light, role: "viewer")
        defer { viewer.close() }
        try await click("Next", in: viewer)
        try await click("Review", in: viewer)
        let review = try await observations(in: viewer).map(\.text)
        XCTAssertTrue(review.contains("Review your answers"), "\(review)")
        XCTAssertFalse(review.contains("Submit answers"))
    }

    private func verifySteps(in window: NSWindow, scheme: ColorScheme) async throws {
        var labels = try await observations(in: window).map(\.text)
        XCTAssertTrue(labels.contains("Question 3 of 4"), "\(labels)")
        XCTAssertFalse(labels.contains("Submit answers"))
        try await capture(window, scheme, "step")
        try await click("Benchmarks", in: window)
        try await click("Next", in: window)
        try await click("Review", in: window)
        labels = try await observations(in: window).map(\.text)
        XCTAssertTrue(labels.contains("Review your answers"), "\(labels)")
        XCTAssertTrue(labels.contains("Submit answers"), "\(labels)")
        XCTAssertTrue(labels.contains("Benchmarks"), "\(labels)")
        try await capture(window, scheme, "review")
        try await click("Benchmarks", in: window)
        labels = try await observations(in: window).map(\.text)
        XCTAssertTrue(labels.contains("Question 3 of 4"), "\(labels)")
    }

    private func intake(single: Bool = false) throws -> QuestionnaireRecord {
        let fixture = try XCTUnwrap(PanelExampleFixtures.load().first { $0.name == "research-intake.json" })
        let spec = single ? PanelSpec(root: "evidence", elements: fixture.spec.elements.filter {
            $0.key == "evidence"
        }) : fixture.spec
        let definition = QuestionnaireDefinition(title: fixture.title, kind: "intake", blocking: true,
            formSpec: spec, answerSchema: .object(["required": .array([.string("evidenceTypes")])]),
            defaults: .object([:]), context: .object([:]))
        return QuestionnaireRecord(requestId: UUID().uuidString, panelId: "panel", requestRevision: 1,
            definitionRevision: 1, state: "open", expiresAt: nil, withdrawalReason: nil,
            definition: definition, submission: nil)
    }

    private func open(_ record: QuestionnaireRecord, _ api: StableReadAPI,
                      _ scheme: ColorScheme, role: String = "admin") async throws -> NSWindow {
        let editor = QuestionnaireEditor(record: record, bossID: "boss",
            answerer: BossIdentity(id: "boss", role: role), service: api, webModel: PanelWebModel(),
            currentTime: { .now }, changed: {})
        let host = NSHostingView(rootView: ScrollView { editor.frame(maxWidth: 560).padding() }
            .environment(\.colorScheme, scheme))
        return try await StableWindowSupport.show(host, scheme: scheme)
    }

    private func observations(in window: NSWindow) async throws -> [(text: String, point: CGPoint)] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await StableWindowSupport.capture(window, directory: directory.path, name: "page")
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(url: directory.appendingPathComponent("page.png")).perform([request])
        return (request.results ?? []).compactMap { result in
            guard let text = result.topCandidates(1).first?.string else { return nil }
            let box = result.boundingBox
            let point = CGPoint(x: box.midX * window.frame.width, y: box.midY * window.frame.height)
            return (text, point)
        }
    }

    private func click(_ label: String, in window: NSWindow) async throws {
        let items = try await observations(in: window)
        let match = items.first { $0.text.hasSuffix(label) }
        let point = try XCTUnwrap(match?.point, "\(label) in \(items.map(\.text))")
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            window.sendEvent(event)
        }
        try await Task.sleep(for: .milliseconds(300))
    }

    private func capture(_ window: NSWindow, _ scheme: ColorScheme, _ page: String) async throws {
        if let directory = ProcessInfo.processInfo.environment["HIBOSS_SNAPSHOT_DIR"] {
            try await StableWindowSupport.capture(window, directory: directory,
                                                  name: "mac-questionnaire-\(page)-\(scheme)")
        }
    }
}
