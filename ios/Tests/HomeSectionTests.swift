// HomeSection tests: title menu cases stay stable for the home switcher.
// Exports: HomeSectionTests covering icons used by HomeView.
// Dependencies: XCTest, HiBoss app target.

import XCTest
@testable import HiBoss

final class HomeSectionTests: XCTestCase {
    func testCasesAndSystemImages() {
        XCTAssertEqual(HomeSection.allCases, [.inbox, .messages])
        XCTAssertEqual(HomeSection.inbox.systemImage, "tray.full")
        XCTAssertEqual(HomeSection.messages.systemImage, "bubble.left.and.bubble.right")
    }
}
