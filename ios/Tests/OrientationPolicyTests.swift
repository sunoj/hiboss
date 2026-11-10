// Unit coverage for the screen-width orientation rule (unfolded Duo rotates, other iPhones do not).
// Exports: OrientationPolicyTests.
// Dependencies: XCTest, UIKit, the app's OrientationPolicy.

import UIKit
import XCTest
@testable import HiBoss

final class OrientationPolicyTests: XCTestCase {
    func testRegularAndFoldedIPhonesStayPortrait() {
        for shortSide: CGFloat in [375, 402, 440, 466, 599.5] {
            XCTAssertEqual(OrientationPolicy.mask(shortSide: shortSide, idiom: .phone), .portrait, "\(shortSide)")
        }
    }

    func testWideIPhoneScreenRotatesExceptUpsideDown() {
        for shortSide: CGFloat in [600, 669] {
            XCTAssertEqual(OrientationPolicy.mask(shortSide: shortSide, idiom: .phone), .allButUpsideDown)
        }
    }

    func testIPadKeepsEveryOrientation() {
        for shortSide: CGFloat in [0, 375, 744, 1024] {
            XCTAssertEqual(OrientationPolicy.mask(shortSide: shortSide, idiom: .pad), .all)
        }
    }
}
