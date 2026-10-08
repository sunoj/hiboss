// Verifies injected plain, MacBook-sized and secondary-display Island geometry.
// Exports: IslandGeometryTests and synthetic display fixtures for native rendering tests.
// Dependencies: XCTest, Foundation geometry, HibossKit constants and IslandGeometry.

import Foundation
import HibossKit
import XCTest
@testable import HibossIsland

final class IslandGeometryTests: XCTestCase {
    func testPlainScreensKeepOriginalCollapsedExpandedAndHotZoneFrames() {
        for frame in [CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: -1920, y: 300, width: 1920, height: 1080)] {
            let geometry = IslandGeometry(screenFrame: frame)
            XCTAssertNil(geometry.notchFrame)
            XCTAssertEqual(geometry.expandedTopInset, 0)
            XCTAssertEqual(geometry.collapsedFrame,
                CGRect(x: frame.midX - 92, y: frame.maxY - 36, width: 184, height: 36))
            XCTAssertEqual(geometry.hotZone, geometry.collapsedFrame)
            XCTAssertEqual(geometry.expandedFrame(contentHeight: 300),
                CGRect(x: frame.midX - 210, y: frame.maxY - 300, width: 420, height: 300))
        }
    }

    func testFourteenInchNotchReservesLabelSpaceAndSideMargins() throws {
        let geometry = IslandNotchFixtures.macBook14
        XCTAssertEqual(geometry.notchFrame, CGRect(x: 651, y: 950, width: 210, height: 32))
        XCTAssertEqual(geometry.collapsedFrame, CGRect(x: 633, y: 914, width: 246, height: 68))
        try assertNotchClearance(geometry)
    }

    func testSixteenInchNotchReservesLabelSpaceAndSideMargins() throws {
        let geometry = IslandNotchFixtures.macBook16
        XCTAssertEqual(geometry.notchFrame, CGRect(x: 756, y: 1085, width: 216, height: 32))
        XCTAssertEqual(geometry.collapsedFrame, CGRect(x: 738, y: 1049, width: 252, height: 68))
        try assertNotchClearance(geometry)
    }

    func testNotchedSecondaryScreenUsesItsOwnGlobalCoordinates() throws {
        let geometry = IslandNotchFixtures.secondary
        XCTAssertEqual(geometry.notchFrame, CGRect(x: -972, y: 1385, width: 216, height: 32))
        XCTAssertEqual(geometry.collapsedFrame, CGRect(x: -990, y: 1349, width: 252, height: 68))
        XCTAssertEqual(geometry.expandedFrame(contentHeight: 300),
            CGRect(x: -1074, y: 1085, width: 420, height: 332))
        try assertNotchClearance(geometry)
    }

    func testScreenLocalAuxiliaryAreasCentreNotchOnOffsetSecondaryScreen() throws {
        let secondary = IslandNotchFixtures.secondary
        let geometry = IslandGeometry(screenFrame: secondary.screenFrame,
            visibleFrame: secondary.visibleFrame, safeAreaTop: 32,
            auxiliaryTopLeftArea: CGRect(x: 0, y: 1085, width: 756, height: 32),
            auxiliaryTopRightArea: CGRect(x: 972, y: 1085, width: 756, height: 32))
        XCTAssertEqual(geometry, secondary)
        XCTAssertEqual(try XCTUnwrap(geometry.notchFrame).midX, secondary.screenFrame.midX)
        XCTAssertEqual(geometry.collapsedFrame, secondary.collapsedFrame)
        XCTAssertEqual(geometry.expandedFrame(contentHeight: 300),
            secondary.expandedFrame(contentHeight: 300))
        try assertNotchClearance(geometry)
    }

    func testAuxiliaryWidthsMustLeavePositiveNotchWidth() {
        for width in [756.0, 800.0] {
            let geometry = IslandGeometry(screenFrame: IslandNotchFixtures.macBook14.screenFrame,
                safeAreaTop: 32,
                auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: width, height: 32),
                auxiliaryTopRightArea: CGRect(x: 1000, y: 950, width: width, height: 32))
            XCTAssertNil(geometry.notchFrame)
            XCTAssertEqual(geometry.expandedTopInset, 32)
        }
    }

    func testExpandedHeightAddsInsetBeforeVisibleFrameCap() {
        for geometry in [IslandNotchFixtures.macBook14, IslandNotchFixtures.macBook16] {
            let short = geometry.expandedFrame(contentHeight: 300)
            XCTAssertEqual(short.height, 332)
            XCTAssertEqual(short.maxY, geometry.screenFrame.maxY)
            let cap = geometry.visibleFrame.height * 0.8
            XCTAssertEqual(geometry.expandedFrame(contentHeight: cap - 16).height, cap)
            XCTAssertEqual(geometry.expandedFrame(contentHeight: 10000).height, cap)
        }
    }

    func testZeroSafeAreaIgnoresAuxiliaryAreas() {
        let geometry = IslandGeometry(screenFrame: IslandNotchFixtures.macBook14.screenFrame,
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 651, height: 32),
            auxiliaryTopRightArea: CGRect(x: 861, y: 950, width: 651, height: 32))
        XCTAssertNil(geometry.notchFrame)
        XCTAssertEqual(geometry.collapsedFrame.size, CGSize(width: 184, height: 36))
    }

    func testMissingAuxiliaryAreasStillReserveSafeAreaForContent() {
        let geometry = IslandGeometry(screenFrame: IslandNotchFixtures.macBook14.screenFrame, safeAreaTop: 32)
        XCTAssertNil(geometry.notchFrame)
        XCTAssertEqual(geometry.expandedTopInset, 32)
        XCTAssertEqual(geometry.collapsedFrame.height, 68)
    }

    private func assertNotchClearance(_ geometry: IslandGeometry) throws {
        let notch = try XCTUnwrap(geometry.notchFrame)
        let bar = geometry.collapsedFrame
        XCTAssertEqual(geometry.expandedTopInset, notch.height)
        XCTAssertEqual(notch.minY - bar.minY, AppConstants.Island.collapsedHeight)
        XCTAssertGreaterThanOrEqual(notch.minX - bar.minX, 18)
        XCTAssertGreaterThanOrEqual(bar.maxX - notch.maxX, 18)
        XCTAssertTrue(geometry.hotZone.contains(notch))
        XCTAssertTrue(geometry.hotZone.contains(bar))
        XCTAssertTrue(geometry.hotZone.contains(CGPoint(x: notch.midX, y: notch.maxY - 1)))
        XCTAssertFalse(geometry.hotZone.contains(CGPoint(x: bar.midX, y: bar.minY - 1)))
    }
}

enum IslandNotchFixtures {
    static let plain = IslandGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 48, width: 1440, height: 827))
    static let macBook14 = notched(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), notchWidth: 210)
    static let macBook16 = notched(frame: CGRect(x: 0, y: 0, width: 1728, height: 1117), notchWidth: 216)
    static let secondary = notched(
        frame: CGRect(x: -1728, y: 300, width: 1728, height: 1117), notchWidth: 216
    )

    private static func notched(frame: CGRect, notchWidth: CGFloat) -> IslandGeometry {
        let sideWidth = (frame.width - notchWidth) / 2
        return IslandGeometry(screenFrame: frame,
            visibleFrame: CGRect(
                x: frame.minX, y: frame.minY + 48, width: frame.width, height: frame.height - 80
            ),
            safeAreaTop: 32,
            auxiliaryTopLeftArea: CGRect(x: frame.minX, y: frame.maxY - 32, width: sideWidth, height: 32),
            auxiliaryTopRightArea: CGRect(x: frame.midX + notchWidth / 2, y: frame.maxY - 32,
                width: sideWidth, height: 32))
    }
}
