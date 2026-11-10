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
}
