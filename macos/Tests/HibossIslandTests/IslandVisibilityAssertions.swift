// Checks the live text geometry, including clipping by the body scroll viewport.
// Exports: assertIslandQuestionIsVisible for live panel and window regression tests.
// Dependencies: AppKit, SwiftUI hosting, and XCTest.

import AppKit
import XCTest
import SwiftUI
@testable import HibossIsland

@MainActor
func assertIslandQuestionIsVisible(in window: NSWindow, fullyVisible: Bool = false,
                                  file: StaticString = #filePath, line: UInt = #line) throws {
    let host = try XCTUnwrap(window.contentView as? NSHostingView<IslandView>, file: file, line: line)
    var frame = host.rootView.questionGeometry.textFrame
    if !host.isFlipped { frame.origin.y = host.bounds.height - frame.maxY }
    var visible = frame.intersection(host.bounds)
    for scroll in islandScrollViews(host) {
        let viewport = host.convert(scroll.contentView.bounds, from: scroll.contentView)
        if frame.intersects(viewport) { visible = visible.intersection(viewport) }
    }
    XCTAssertGreaterThanOrEqual(visible.height, 16, "At least one question line must be visible",
                                file: file, line: line)
    XCTAssertGreaterThan(visible.width, 0, file: file, line: line)
    if fullyVisible {
        XCTAssertEqual(visible.height, frame.height, accuracy: 0.5,
                       "The complete compact question must be visible", file: file, line: line)
    }
}

@MainActor
private func islandScrollViews(_ view: NSView) -> [NSScrollView] {
    view.subviews.flatMap { child in
        (child as? NSScrollView).map { [$0] } ?? islandScrollViews(child)
    }
}
