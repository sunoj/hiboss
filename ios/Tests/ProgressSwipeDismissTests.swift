// Unit coverage for zoom-1 swipe-down dismiss policy.
// Exports: MediaSwipeDismissTests.
// Dependencies: XCTest, HiBoss app target.

import SwiftUI
import XCTest
@testable import HiBoss

final class MediaSwipeDismissTests: XCTestCase {
    @MainActor
    func testFittedZoomSurfaceLeavesPansToPagerButZoomedSurfaceCanPan() {
        let view = MediaZoomView(pageID: "page", onZoomed: { _ in }, onDismissDrag: { _ in },
                                 onDismiss: {}, onSingleTap: {}) { Color.clear }
        let coordinator = view.makeCoordinator()
        let scroll = coordinator.makeScrollView()
        scroll.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        coordinator.syncFrame(scroll)
        XCTAssertFalse(scroll.gestureRecognizerShouldBegin(scroll.panGestureRecognizer))
        scroll.setZoomScale(2, animated: false)
        XCTAssertTrue(scroll.gestureRecognizerShouldBegin(scroll.panGestureRecognizer))
    }

    func testShouldBeginOnlyForDownwardPanAtZoomOne() {
        XCTAssertTrue(MediaSwipeDismiss.shouldBegin(zoomScale: 1, velocity: .zero))
        XCTAssertTrue(
            MediaSwipeDismiss.shouldBegin(zoomScale: 1, velocity: CGPoint(x: 0, y: 40))
        )
        XCTAssertTrue(
            MediaSwipeDismiss.shouldBegin(zoomScale: 1, velocity: CGPoint(x: 20, y: 50))
        )
        XCTAssertFalse(
            MediaSwipeDismiss.shouldBegin(zoomScale: 1, velocity: CGPoint(x: 0, y: -40))
        )
        XCTAssertFalse(
            MediaSwipeDismiss.shouldBegin(zoomScale: 1, velocity: CGPoint(x: 80, y: 20))
        )
        XCTAssertFalse(
            MediaSwipeDismiss.shouldBegin(zoomScale: 2, velocity: CGPoint(x: 0, y: 80))
        )
    }

    func testDragOffsetIgnoresUpwardAndZoomedPans() {
        XCTAssertEqual(
            MediaSwipeDismiss.dragOffset(translation: CGPoint(x: 0, y: 80), zoomScale: 1),
            80
        )
        XCTAssertEqual(
            MediaSwipeDismiss.dragOffset(translation: CGPoint(x: 0, y: -40), zoomScale: 1),
            0
        )
        XCTAssertEqual(
            MediaSwipeDismiss.dragOffset(translation: CGPoint(x: 0, y: 80), zoomScale: 2),
            0
        )
    }

    func testShouldDismissPastThresholdOnlyAtZoomOne() {
        XCTAssertFalse(MediaSwipeDismiss.shouldDismiss(offset: 120, zoomScale: 1))
        XCTAssertTrue(MediaSwipeDismiss.shouldDismiss(offset: 121, zoomScale: 1))
        XCTAssertFalse(MediaSwipeDismiss.shouldDismiss(offset: 400, zoomScale: 2))
    }
}
