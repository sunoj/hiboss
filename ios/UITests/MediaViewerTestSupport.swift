// Shared behavioral assertions for every media entry point's UIKit zoom surface.
// Exports assertMediaPinchZoom and mediaZoomScroll; values reflect the actual UIScrollView scale.
// Dependencies: XCTest and the shared MediaViewer accessibility contract.

import XCTest

func mediaZoomScroll(_ app: XCUIApplication) -> XCUIElement {
    let query = app.scrollViews.matching(NSPredicate(
        format: "identifier BEGINSWITH %@", "media-zoom-scroll"
    ))
    _ = query.firstMatch.waitForExistence(timeout: 5)
    return query.allElementsBoundByIndex.first { $0.isHittable } ?? query.firstMatch
}

func assertMediaPinchZoom(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    let scroll = mediaZoomScroll(app)
    XCTAssertTrue(scroll.exists, file: file, line: line)
    scroll.pinch(withScale: 2, velocity: 1)
    let zoomed = NSPredicate(format: "value == %@", "Zoomed")
    let expectation = XCTNSPredicateExpectation(predicate: zoomed, object: scroll)
    XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed, file: file, line: line)
}
