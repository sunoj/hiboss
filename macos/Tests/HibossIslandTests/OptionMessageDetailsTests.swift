// Verifies the island's collapsible message details: the length policy and rendered heights.
// Exports: OptionMessageDetailsTests (logic and ImageRenderer only; opens no windows).
// Dependencies: SwiftUI ImageRenderer, XCTest, and the production details views.

import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class OptionMessageDetailsTests: XCTestCase {
    private let longDetails = """
        aid 11.17.0 is installed on this Mac and on air.
        Proposed `[project] stage` mapping for five repositories:
        - hiboss: release
        - ai-dispatch: build
        - smart-router: build
        - aich: explore
        Nothing is pushed; each config is committed locally.
        """

    func testShortDetailsNeedNoToggle() {
        XCTAssertFalse(OptionDetailsPolicy.isLong("Commit stage to 5 repos locally; no push"))
        XCTAssertFalse(OptionDetailsPolicy.isLong("one\ntwo\nthree"))
        XCTAssertFalse(OptionDetailsPolicy.isLong(String(repeating: "界", count: 84)))
    }

    func testManyLinesOrWideTextCollapse() {
        XCTAssertTrue(OptionDetailsPolicy.isLong("one\ntwo\nthree\nfour"))
        XCTAssertTrue(OptionDetailsPolicy.isLong(String(repeating: "word ", count: 40)))
        XCTAssertTrue(OptionDetailsPolicy.isLong(String(repeating: "界", count: 85)))
        XCTAssertTrue(OptionDetailsPolicy.isLong(longDetails))
    }

    func testCollapsedPreviewIsShorterThanExpandedDetails() throws {
        let collapsed = try renderedHeight(OptionMessageDetails(text: longDetails, isExpanded: .constant(false)))
        let expanded = try renderedHeight(OptionMessageDetails(text: longDetails, isExpanded: .constant(true)))
        XCTAssertLessThan(collapsed, expanded)
        // Three callout lines plus the toggle, never the whole message.
        XCTAssertLessThan(collapsed, 100, "collapsed preview grew to \(collapsed)")
    }

    func testQuestionBodyGrowsWithDetails() throws {
        let plain = try renderedHeight(OptionMessageBody(text: "Apply the mapping?", attachment: nil))
        let detailed = try renderedHeight(OptionMessageBody(text: "Apply the mapping?",
            details: "Commit stage to 5 repos locally; no push", attachment: nil))
        XCTAssertGreaterThan(detailed, plain + 10)
    }

    private func renderedHeight(_ view: some View) throws -> CGFloat {
        let renderer = ImageRenderer(content: view.frame(width: 384)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color.black).environment(\.colorScheme, .dark))
        renderer.scale = 1
        return try XCTUnwrap(renderer.cgImage).height.cgFloat
    }
}

private extension Int {
    var cgFloat: CGFloat { CGFloat(self) }
}
