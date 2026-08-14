// Tests for the login-item status mapping shown in the General settings pane.
// Covers: registered states, approval prompt, unbundled builds, and failures.
// Dependencies: XCTest, ServiceManagement.

import ServiceManagement
import XCTest
@testable import HibossIsland

@MainActor
final class LaunchAtLoginTests: XCTestCase {
    func testApprovalPendingCountsAsRegistered() {
        XCTAssertTrue(LaunchAtLoginController.isRegistered(.enabled))
        XCTAssertTrue(LaunchAtLoginController.isRegistered(.requiresApproval))
        XCTAssertFalse(LaunchAtLoginController.isRegistered(.notRegistered))
        XCTAssertFalse(LaunchAtLoginController.isRegistered(.notFound))
    }

    func testExplanationPointsAtSystemSettingsWhenApprovalIsPending() {
        let text = LaunchAtLoginController.explanation(for: .requiresApproval, failure: nil)
        XCTAssertEqual(
            text,
            L("Approve HiBoss Island under System Settings › General › Login Items to finish enabling this.")
        )
    }

    func testExplanationDistinguishesEnabledFromNotRegistered() {
        XCTAssertNotEqual(
            LaunchAtLoginController.explanation(for: .enabled, failure: nil),
            LaunchAtLoginController.explanation(for: .notRegistered, failure: nil)
        )
    }

    func testFailureOverridesStatusText() {
        XCTAssertEqual(
            LaunchAtLoginController.explanation(for: .enabled, failure: "Operation not permitted"),
            "Operation not permitted"
        )
    }
}
