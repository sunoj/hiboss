// Checks the rendered session status for labelled activity and a single freshness source.
// Exports: SessionStatusPresentationTests; the header must not duplicate toolbar freshness.
// Dependencies: AppKit, SwiftUI, Vision, and synthetic session inventory.

import AppKit
import HibossKit
import SwiftUI
import Vision
import XCTest
@testable import HibossIsland

@MainActor
final class SessionStatusPresentationTests: XCTestCase {
    func testHeaderLabelsActivityAndLeavesFreshnessToWindowToolbar() async throws {
        let session = ProjectSession(id: "session", projectId: nil, projectSlug: nil, branch: nil,
            status: "working", statusText: "Awaiting next input",
            lastSeenAt: AttentionTestSupport.iso(.now.addingTimeInterval(-379)))
        let context = SessionContext(id: session.id,
            snapshot: OverviewSnapshot(history: [], live: nil, now: .now), inventory: [session])
        let host = NSHostingView(rootView: SessionHeader(context: context, connection: .connected))
        let window = try await StableWindowSupport.show(host)
        defer { window.close() }
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
        let words = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
        XCTAssertTrue(words.contains("Status: working"), words)
        XCTAssertTrue(words.contains("Listening"), words)
        XCTAssertFalse(words.contains("Updated"), words)
    }
}
