// Off-window regression: an answered decision leaves Needs you and renders as answered in place.
// Exports: SessionThreadAnswerRenderingTests; no desktop windows are opened.
// Dependencies: AppKit, SwiftUI, Vision, SessionThreadFixtures, and the session thread view.

import AppKit
import HibossKit
import SwiftUI
import Vision
import XCTest
@testable import HibossIsland

@MainActor
final class SessionThreadAnswerRenderingTests: XCTestCase {
    func testAnsweringUpdatesTheSameHostLikeAFreshRender() throws {
        let now = Date.now
        let open = SessionThreadFixtures.history(now: now)
        let answered = open.map { $0.id.rawValue == "open" ? replied($0) : $0 } + [HistoryMessage(
            id: MessageID(rawValue: "open-reply"), body: "Focused checks", agentName: "Build Agent",
            direction: "boss_to_agent", status: "sent", priority: "normal", replyTo: "open",
            createdAt: AttentionTestSupport.iso(now), targetSessionId: "thread-demo")]
        let host = NSHostingView(rootView: view(OverviewSnapshot(history: open, live: nil, now: now,
            requiredInputs: open.filter { $0.id.rawValue == "open" }, requiredInputLoaded: true)))
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 1400)
        _ = try text(of: host)
        let answeredSnapshot = OverviewSnapshot(history: answered, live: nil, now: now,
            requiredInputs: [], requiredInputLoaded: true)
        XCTAssertEqual(answeredSnapshot.answerability.state(for: "open"), .closed)
        host.rootView = view(answeredSnapshot)
        let updated = try text(of: host)
        let fresh = NSHostingView(rootView: view(answeredSnapshot))
        fresh.frame = host.frame
        XCTAssertEqual(updated, try text(of: fresh), "the answered decision kept its open card")
    }

    private func replied(_ message: HistoryMessage) -> HistoryMessage {
        HistoryMessage(id: message.id, body: message.body, agentName: message.agentName,
            direction: message.direction, status: "replied", priority: message.priority,
            replyTo: message.replyTo, metadata: message.metadata, expiresAt: message.expiresAt,
            createdAt: message.createdAt, sessionId: message.sessionId, sessionLabel: message.sessionLabel)
    }

    private func view(_ snapshot: OverviewSnapshot) -> AnyView {
        AnyView(SessionThreadView(
            context: SessionContext(id: "thread-demo", snapshot: snapshot, inventory: []),
            flow: OptionFlowStore(), reply: AttentionReplyState(), connection: .connected,
            onChoose: { _, _ in nil })
            .background(TodayStyle.ground)
            .frame(width: 900, height: 1400))
    }

    private func text(of host: NSHostingView<AnyView>) throws -> [String] {
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: try XCTUnwrap(bitmap.cgImage)).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }
}
