// Covers the connection gate that suppresses Home's all-clear illustration.
// Exports: HomeConnectionStatusTests; complete fetch coverage is checked by HomeView.
// Dependencies: XCTest, HiBoss and HibossKit ConnectionState.

import HibossKit
import XCTest
@testable import HiBoss

final class HomeConnectionStatusTests: XCTestCase {
    func testFailureIsTerminalRatherThanAConnectionWait() {
        XCTAssertTrue(HomeConnectionStatus.isFailure(.failed("Timeout")))
        XCTAssertTrue(HomeConnectionStatus.isFailure(.disconnected))
        XCTAssertFalse(HomeConnectionStatus.isFailure(.connecting))
        XCTAssertFalse(HomeConnectionStatus.isFailure(.connected))
    }

    func testOnlyConnectedStreamAllowsAnAllClearCandidate() {
        XCTAssertNil(HomeConnectionStatus.notice(for: .connected))
        for state in [ConnectionState.connecting, .disconnected, .failed("Unavailable")] {
            XCTAssertNotNil(HomeConnectionStatus.notice(for: state))
        }
    }

    func testOfflineStatesExplainHowToRecover() {
        for state in [ConnectionState.disconnected, .failed("Unavailable")] {
            let notice = HomeConnectionStatus.notice(for: state)
            XCTAssertTrue(notice?.contains("refresh") == true)
            XCTAssertTrue(notice?.contains("Settings") == true)
        }
        XCTAssertEqual(HomeConnectionStatus.notice(for: .connecting), "Connecting…")
    }
}
