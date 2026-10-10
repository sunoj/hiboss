// Renders closed Island actions and clicks choices while their requests are pending.
// Exports: ChoicePresentationTests for resolved copy and immediate option feedback.
// Dependencies: AppKit, SwiftUI, Vision OCR, and the production decision views.

import AppKit
import HibossKit
import SwiftUI
import Vision
import XCTest
@testable import HibossIsland

@MainActor
final class ChoicePresentationTests: XCTestCase {
    func testClosedIslandActionsNeverSayChecking() async throws {
        let message = OptionMessage.fixture(id: "closed", options: ["Ship", "Hold"])
        let overview = OverviewStore()
        overview.update(history: [TodayProjection.historyMessage(from: message)], live: nil,
            closedDecisionIDs: [message.id])
        let view = IslandView(flow: OptionFlowStore(), reply: AttentionReplyState(), overview: overview)
        let host = NSHostingView(rootView: view.fixedActions(message)
            .frame(width: 180, height: 80).scaleEffect(2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .light))
        let window = window(host)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(200))
        let labels = try recognize(host).map(\.text)
        XCTAssertFalse(labels.contains { $0.contains("Checking") }, "\(labels)")
        XCTAssertTrue(labels.contains { $0.contains("No longer open") }, "\(labels)")
    }

    func testTodayAndIslandImmediatelyShowSendingAndDisableOtherChoices() async throws {
        let item = AttentionItem(message: AttentionTestSupport.ask(id: "question",
            options: ["Ship", "Hold"]), group: .priority)
        for island in [false, true] {
            var choices: [String] = []
            let pending = ChoicePendingState()
            let view = ChoicePendingFixture(item: item, island: island, pending: pending,
                choose: { choices.append($0) })
            let host = NSHostingView(rootView: view.padding(20))
            let window = window(host)
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(200))
            try click("Ship", in: host, window: window)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(choices, ["Ship"])
            let labels = try recognize(host).map(\.text)
            XCTAssertTrue(labels.contains { $0.contains("Sending") }, "\(labels)")
            try click("Hold", in: host, window: window)
            XCTAssertEqual(choices, ["Ship"], "Other choices must disable immediately")
            pending.submitting = true
            try await Task.sleep(for: .milliseconds(100))
            pending.submitting = false
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertFalse(try recognize(host).contains { $0.text.contains("Sending") })
            try click("Hold", in: host, window: window)
            XCTAssertEqual(choices, ["Ship", "Hold"], "A failed request must allow another choice")
        }
    }

    private func click(_ label: String, in host: NSView, window: NSWindow) throws {
        let text = try XCTUnwrap(recognize(host).first { $0.text.contains(label) })
        let point = host.convert(NSPoint(x: text.bounds.midX * host.bounds.width,
            y: (host.isFlipped ? 1 - text.bounds.midY : text.bounds.midY) * host.bounds.height), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            window.sendEvent(event)
        }
    }

    private func recognize(_ host: NSView) throws -> [(text: String, bounds: CGRect)] {
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        if let directory = ProcessInfo.processInfo.environment["HIBOSS_SNAPSHOT_DIR"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("choice-feedback.png"))
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
        return (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map { ($0.string, observation.boundingBox) }
        }
    }

    private func window(_ host: NSView) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 500, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        return window
    }
}

@MainActor
private final class ChoicePendingState: ObservableObject {
    @Published var submitting = false
}

private struct ChoicePendingFixture: View {
    let item: AttentionItem
    let island: Bool
    @ObservedObject var pending: ChoicePendingState
    let choose: (String) -> Void

    var body: some View {
        if island {
            OptionMediaPicker(options: item.options, media: [], defaultOption: nil,
                isSubmitting: pending.submitting, choose: choose)
        } else {
            TodayDecisionCard(item: item, now: .now, isSelected: false,
                isSubmitting: pending.submitting, error: nil, onSelect: {}, onChoose: choose)
        }
    }
}
