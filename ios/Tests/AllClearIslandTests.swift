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

    func testIslandRendersStillFrame() throws {
        let renderer = ImageRenderer(content: AllClearIslandView())
        renderer.scale = 1
        let image = renderer.uiImage
        XCTAssertNotNil(image)
        XCTAssertEqual(image?.size, CGSize(width: 168, height: 148))
        let cgImage = try XCTUnwrap(image?.cgImage)
        let pixels = try rgbaPixels(cgImage)
        let alpha = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
        XCTAssertGreaterThan(alpha.filter { $0 > 0 }.count, cgImage.width * cgImage.height / 2)
        XCTAssertEqual(alpha.first, 0)
        XCTAssertEqual(alpha.last, 0)
    }
}
