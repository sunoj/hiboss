// Checks the rendered session status for labelled activity and a single freshness source.
// Exports: SessionStatusPresentationTests; the header must not duplicate the toolbar Live chip.
// Dependencies: AppKit, SwiftUI, Vision, and synthetic session inventory.

import AppKit
import HibossKit
import SwiftUI
import Vision
import XCTest
@testable import HibossIsland

@MainActor
final class SessionStatusPresentationTests: XCTestCase {
    func testHeaderLeadsWithActivityAndLeavesConnectionToWindowToolbar() async throws {
        let session = ProjectSession(id: "session", projectId: nil, projectSlug: nil, branch: nil,
            status: "working", statusText: "Awaiting next input",
            lastSeenAt: AttentionTestSupport.iso(.now.addingTimeInterval(-379)))
        let context = SessionContext(id: session.id,
            snapshot: OverviewSnapshot(history: [], live: nil, now: .now), inventory: [session])
        // The header has no fill of its own; in the app it sits on the session's ground.
        let host = NSHostingView(rootView: SessionHeader(context: context)
            .background(TodayStyle.ground))
        let window = try await StableWindowSupport.show(host)
        defer { window.close() }
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
        let words = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
        XCTAssertTrue(words.contains("Awaiting next input"), words)
        XCTAssertFalse(words.contains("Listening"), "Connection is the toolbar chip: \(words)")
        XCTAssertFalse(words.contains("Updated"), words)
    }
}
