// Unit coverage for exclusive HIBOSS_DEMO_* deep-link resolution.
// Exports: DemoLaunchRouteTests.
// Dependencies: XCTest.

import XCTest
@testable import HiBoss

final class DemoLaunchRouteTests: XCTestCase {
    func testBareDemoLeavesInbox() {
        XCTAssertEqual(DemoLaunchRoute.resolve(env: ["HIBOSS_DEMO": "1"]), .none)
    }

    func testOpenWinsOverSessionAndResolved() {
        let env = [
            "HIBOSS_DEMO": "1",
            "HIBOSS_DEMO_OPEN": "demo-msg-1",
            "HIBOSS_DEMO_SESSION": "1",
            "HIBOSS_DEMO_RESOLVED": "1",
        ]
        XCTAssertEqual(
            DemoLaunchRoute.resolve(env: env),
            .open(.init(rawValue: "demo-msg-1"))
        )
    }

    func testResolvedWinsOverStaleSession() {
        // Simulator `launchctl setenv HIBOSS_DEMO_SESSION` outlives screenshot runs.
        let env = [
            "HIBOSS_DEMO": "1",
            "HIBOSS_DEMO_SESSION": "1",
            "HIBOSS_DEMO_RESOLVED": "1",
        ]
        XCTAssertEqual(DemoLaunchRoute.resolve(env: env), .resolved)
    }

    func testSessionOnlyWhenExplicit() {
        XCTAssertEqual(
            DemoLaunchRoute.resolve(env: ["HIBOSS_DEMO": "1", "HIBOSS_DEMO_SESSION": "1"]),
            .session(id: "sess-deploy", label: "prod-release")
        )
    }

    func testEmptyOpenDoesNotCount() {
        XCTAssertEqual(
            DemoLaunchRoute.resolve(env: ["HIBOSS_DEMO_OPEN": "", "HIBOSS_DEMO_SESSION": "1"]),
            .session(id: "sess-deploy", label: "prod-release")
        )
    }
}
