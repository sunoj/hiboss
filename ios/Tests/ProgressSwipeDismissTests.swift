// Unit coverage for zoom-1 swipe-down dismiss policy.
// Exports: ProgressSwipeDismissTests.
// Dependencies: XCTest, HiBoss app target.

import XCTest
@testable import HiBoss

final class ProgressSwipeDismissTests: XCTestCase {
    func testShouldBeginOnlyForDownwardPanAtZoomOne() {
        XCTAssertTrue(ProgressSwipeDismiss.shouldBegin(zoomScale: 1, velocity: .zero))
        XCTAssertTrue(
            ProgressSwipeDismiss.shouldBegin(zoomScale: 1, velocity: CGPoint(x: 0, y: 40))
        )
        XCTAssertTrue(
            ProgressSwipeDismiss.shouldBegin(zoomScale: 1, velocity: CGPoint(x: 20, y: 50))
        )
        XCTAssertFalse(
            ProgressSwipeDismiss.shouldBegin(zoomScale: 1, velocity: CGPoint(x: 0, y: -40))
        )
        XCTAssertFalse(
            ProgressSwipeDismiss.shouldBegin(zoomScale: 1, velocity: CGPoint(x: 80, y: 20))
        )
        XCTAssertFalse(
            ProgressSwipeDismiss.shouldBegin(zoomScale: 2, velocity: CGPoint(x: 0, y: 80))
        )
    }

    func testDragOffsetIgnoresUpwardAndZoomedPans() {
        XCTAssertEqual(
            ProgressSwipeDismiss.dragOffset(translation: CGPoint(x: 0, y: 80), zoomScale: 1),
            80
        )
        XCTAssertEqual(
            ProgressSwipeDismiss.dragOffset(translation: CGPoint(x: 0, y: -40), zoomScale: 1),
            0
        )
        XCTAssertEqual(
            ProgressSwipeDismiss.dragOffset(translation: CGPoint(x: 0, y: 80), zoomScale: 2),
            0
        )
    }

    func testShouldDismissPastThresholdOnlyAtZoomOne() {
        XCTAssertFalse(ProgressSwipeDismiss.shouldDismiss(offset: 120, zoomScale: 1))
        XCTAssertTrue(ProgressSwipeDismiss.shouldDismiss(offset: 121, zoomScale: 1))
        XCTAssertFalse(ProgressSwipeDismiss.shouldDismiss(offset: 400, zoomScale: 2))
    }
}
