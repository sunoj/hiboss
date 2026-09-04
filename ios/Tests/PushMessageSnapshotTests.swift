// Verifies decoding the message snapshot carried by an APNs notification.
// Exports: PushMessageSnapshotTests for cache prewarming and malformed input.
// Dependencies: XCTest, HibossKit, PushMessageSnapshot, and AppRouter.

import HibossKit
import XCTest
@testable import HiBoss

final class PushMessageSnapshotTests: XCTestCase {
    func testDecodesNotificationMessageIntoDetailCacheValue() throws {
        let cached = try XCTUnwrap(PushMessageSnapshot.decode(from: Self.makeUserInfo()))
        let detail = cached.detail

        XCTAssertFalse(cached.requiresRefresh)
        XCTAssertEqual(detail.message.id, "message-1")
        XCTAssertEqual(detail.message.body, "Ship it?")
        XCTAssertEqual(detail.message.options, ["Approve", "Wait"])
        XCTAssertEqual(detail.replies, [])
    }

    func testRejectsMalformedNotificationMessage() {
        XCTAssertNil(PushMessageSnapshot.decode(from: ["message": ["id": "message-1"]]))
    }

    func testBuildsImmediatePreviewFromCurrentProductionNotification() throws {
        let cached = try XCTUnwrap(PushMessageSnapshot.decode(from: [
            "aps": [
                "alert": [
                    "title": "smart-router/perf/723-rh-fast-mode",
                    "body": "PR #757 review done. Post it, dispatch fixes, or hold?",
                ],
            ],
            "messageId": "message-757",
            "agentName": "Review Agent",
            "priority": "high",
            "direction": "agent_to_boss",
            "options": ["Post review", "Dispatch fixes", "Hold"],
        ]))

        XCTAssertTrue(cached.requiresRefresh)
        XCTAssertEqual(cached.detail.message.id, "message-757")
        XCTAssertEqual(cached.detail.message.body, "PR #757 review done. Post it, dispatch fixes, or hold?")
        XCTAssertEqual(cached.detail.message.options, ["Post review", "Dispatch fixes", "Hold"])
    }

    @MainActor
    func testRouterCarriesMatchingSnapshotUntilNavigationFinishes() throws {
        let cached = try XCTUnwrap(PushMessageSnapshot.decode(from: Self.makeUserInfo()))
        AppRouter.shared.open(messageID: "message-1", cachedMessage: cached)

        XCTAssertEqual(AppRouter.shared.pendingMessage?.cachedMessage, cached)
        AppRouter.shared.finishOpening("message-1")
        XCTAssertNil(AppRouter.shared.pendingMessage)
    }

    private static func makeUserInfo() -> [AnyHashable: Any] {
        [
            "message": [
                "id": "message-1",
                "body": "Ship it?",
                "agent_name": "Release Agent",
                "direction": "agent_to_boss",
                "status": "sent",
                "priority": "high",
                "mode": "async",
                "metadata": ["options": ["Approve", "Wait"]],
                "created_at": "2026-09-04T01:00:00Z",
            ],
        ]
    }
}
