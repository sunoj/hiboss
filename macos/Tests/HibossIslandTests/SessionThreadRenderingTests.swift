// Off-window rendering regression for the real session message surface.
// Exports: SessionThreadRenderingTests; no desktop windows are opened.
// Dependencies: AppKit, SwiftUI, Vision, and the shared session fixture.

import AppKit
import HibossKit
import SwiftUI
import Vision
import XCTest
@testable import HibossIsland

@MainActor
final class SessionThreadRenderingTests: XCTestCase {
    func testSessionSurfaceRendersEveryMergedUpdate() async throws {
        let now = Date.now
        let history = SessionThreadFixtures.history(now: now)
        let snapshot = OverviewSnapshot(history: history, live: nil, now: now,
            requiredInputs: history, requiredInputLoaded: true)
        let host = NSHostingView(rootView: SessionThreadView(
            context: SessionContext(id: "thread-demo", snapshot: snapshot, inventory: []),
            flow: OptionFlowStore(), reply: AttentionReplyState(), connection: .connected,
            onChoose: { _, _ in nil })
            // SessionView paints the ground behind this surface in the app.
            .background(TodayStyle.ground)
            // Vision drops a line from a page that is mostly empty, so the canvas stays near the content.
            .frame(width: 900, height: 1200))
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 1200)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let pixels = try XCTUnwrap(bitmap.cgImage)
        if let directory = ProcessInfo.processInfo.environment["HIBOSS_SNAPSHOT_DIR"] {
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent("session-thread-render.png"))
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: pixels).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
        for update in history.suffix(3) {
            XCTAssertTrue(text.contains(update.body), "Missing \(update.body): \(text)")
        }
    }
}
