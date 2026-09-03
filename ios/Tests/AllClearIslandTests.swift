// All-clear island: motion stays still under Reduce Motion, colours load from the catalog.
// Exports: AllClearIslandTests covering phase math, leaf geometry, and named colours.
// Dependencies: XCTest, SwiftUI ImageRenderer, HiBoss app target.

import SwiftUI
import UIKit
import XCTest
@testable import HiBoss

@MainActor
final class AllClearIslandTests: XCTestCase {
    func testReducedMotionIsAStillFrame() {
        let t0 = Date(timeIntervalSinceReferenceDate: 100)
        let t1 = Date(timeIntervalSinceReferenceDate: 107)
        let a = AllClearIslandMotion.phase(at: t0, reducedMotion: true)
        let b = AllClearIslandMotion.phase(at: t1, reducedMotion: true)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.breathe, 0)
        XCTAssertEqual(a.frond, 0)
    }

    func testPhaseChangesOverTimeWhenMotionIsAllowed() {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        let t1 = Date(timeIntervalSinceReferenceDate: 2)
        XCTAssertNotEqual(
            AllClearIslandMotion.phase(at: t0, reducedMotion: false),
            AllClearIslandMotion.phase(at: t1, reducedMotion: false)
        )
    }

    func testPhaseStaysInRange() {
        let phase = AllClearIslandMotion.phase(
            at: Date(timeIntervalSinceReferenceDate: 1.7),
            reducedMotion: false
        )
        XCTAssertLessThanOrEqual(abs(phase.breathe), 1)
        XCTAssertLessThanOrEqual(abs(phase.frond), 0.11)
        XCTAssertGreaterThanOrEqual(phase.shimmer, 0)
        XCTAssertLessThanOrEqual(phase.shimmer, 1)
    }

    func testLeafPathHasExtent() {
        let path = AllClearIslandScene.leaf(from: .zero, length: 30, angle: -.pi / 2, width: 6)
        XCTAssertFalse(path.isEmpty)
        XCTAssertGreaterThan(path.boundingRect.height, 20)
    }

    func testNamedColorsLoadFromAppCatalog() {
        let bundle = Bundle(identifier: "ai.hiboss.app")
        XCTAssertNotNil(bundle)
        for name in IslandSwatch.names {
            XCTAssertNotNil(UIColor(named: name, in: bundle, compatibleWith: nil), name)
        }
        XCTAssertEqual(IslandSwatch.names.count, 11)
    }

    func testIslandRendersStillFrame() {
        let renderer = ImageRenderer(content: AllClearIslandView())
        renderer.scale = 1
        let image = renderer.uiImage
        XCTAssertNotNil(image)
        XCTAssertEqual(image?.size, CGSize(width: 168, height: 148))
    }

    func testAllClearClaimsEverythingAboveTheFooter() {
        // The block fills the free space, so the island centres in it and the footer
        // lands on the bottom edge — without estimating how tall the copy renders.
        XCTAssertEqual(
            InboxResolvedPlacement.allClearHeight(listHeight: 600, bottomInset: 0, hasResolved: true),
            600 - InboxResolvedPlacement.label
        )
        XCTAssertEqual(
            InboxResolvedPlacement.allClearHeight(listHeight: 600, bottomInset: 0, hasResolved: false),
            600
        )
        // The list runs under the floating tab bar; ignoring that inset buries the footer.
        XCTAssertEqual(
            InboxResolvedPlacement.allClearHeight(listHeight: 600, bottomInset: 90, hasResolved: true),
            600 - 90 - InboxResolvedPlacement.label
        )
        // A short list must not collapse the illustration to nothing.
        XCTAssertEqual(
            InboxResolvedPlacement.allClearHeight(listHeight: 80, bottomInset: 0, hasResolved: true),
            160
        )
    }

    func testSpacerOnlySeparatesAPopulatedQueueFromTheFooter() {
        XCTAssertEqual(InboxResolvedPlacement.spacerHeight(pendingIsEmpty: true, listHeight: 600), 0)
        XCTAssertEqual(InboxResolvedPlacement.spacerHeight(pendingIsEmpty: false, listHeight: 600), 40)
    }
}
