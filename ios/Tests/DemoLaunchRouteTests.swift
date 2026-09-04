// Unit coverage for exclusive HIBOSS_DEMO_* deep-link resolution.
// Exports: DemoLaunchRouteTests.
// Dependencies: XCTest, HibossKit, and the app's notification router.

import HibossKit
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

    func testNotificationSnapshotWinsOverOtherDemoRoutes() {
        let env = [
            "HIBOSS_DEMO_NOTIFICATION_OPEN": "cached-message",
            "HIBOSS_DEMO_OPEN": "network-message",
            "HIBOSS_DEMO_RESOLVED": "1",
        ]
        XCTAssertEqual(
            DemoLaunchRoute.resolve(env: env),
            .notification(.init(rawValue: "cached-message"))
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

    @MainActor
    func testNotificationRouterDoesNotClearANewerMessage() {
        let first = MessageID(rawValue: "first")
        let second = MessageID(rawValue: "second")
        AppRouter.shared.open(messageID: first.rawValue)
        AppRouter.shared.open(messageID: second.rawValue)

        AppRouter.shared.finishOpening(first)
        XCTAssertEqual(AppRouter.shared.pendingMessageID, second)

        AppRouter.shared.finishOpening(second)
        XCTAssertNil(AppRouter.shared.pendingMessageID)
    }
}
