// Unit coverage for the width rule that splits Today and Sessions into two columns.
// Exports: ColumnLayoutTests.
// Dependencies: XCTest, the app's ColumnLayout.

import XCTest
@testable import HiBoss

final class ColumnLayoutTests: XCTestCase {
    func testWideLandscapeWindowsShowTwoColumns() {
        XCTAssertEqual(ColumnLayout.listWidth(forAvailableWidth: 951), 380, "unfolded Duo, landscape")
        XCTAssertEqual(ColumnLayout.listWidth(forAvailableWidth: 1133), 420, "iPad mini, landscape")
        XCTAssertEqual(ColumnLayout.listWidth(forAvailableWidth: 1366), 420, "the list width is capped")
    }

    func testPortraitAndPhoneWindowsShowOneColumn() {
        for width: CGFloat in [320, 375, 393, 402, 430, 440, 669, 744, 899.5] {
            XCTAssertNil(ColumnLayout.listWidth(forAvailableWidth: width), "\(width)")
        }
    }

    /// The unfolded Duo in landscape: 951 pt wide, an 84 pt rail on the right, a 380 pt list column.
    func testOnlyTheColumnAtTheRailYieldsToIt() {
        let rail: CGFloat = 84, width: CGFloat = 951
        let listOverlap = 380 - (width - rail)
        XCTAssertEqual(ColumnLayout.insetCorrection(received: rail, overlap: listOverlap), -rail,
                       "the list never reaches the rail, so it gives back the inset it was handed")
        XCTAssertEqual(ColumnLayout.insetCorrection(received: rail, overlap: width - (width - rail)), 0,
                       "the detail column at the edge keeps the rail inset")
        XCTAssertEqual(ColumnLayout.insetCorrection(received: 0, overlap: listOverlap), 0,
                       "no rail (iPad, portrait iPhone): nothing changes")
        XCTAssertEqual(ColumnLayout.insetCorrection(received: rail, overlap: 30), -54,
                       "a column partly under the rail keeps the part it covers")
    }

    func testALowerThresholdSplitsANarrowerWindow() {
        XCTAssertEqual(ColumnLayout.listWidth(forAvailableWidth: 466, minWidth: 400), 186)
        XCTAssertNil(ColumnLayout.listWidth(forAvailableWidth: 466))
    }
}
