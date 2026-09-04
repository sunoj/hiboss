// Verifies decoding the message snapshot carried by an APNs notification.
// Exports: PushMessageSnapshotTests for cache prewarming and malformed input.
// Dependencies: XCTest, HibossKit, PushMessageSnapshot, and AppRouter.

import HibossKit
import XCTest
@testable import HiBoss

final class PushMessageSnapshotTests: XCTestCase {
    func testDecodesNotificationMessageIntoDetailCacheValue() throws {
        let detail = try XCTUnwrap(PushMessageSnapshot.decode(from: Self.makeUserInfo()))

        XCTAssertEqual(detail.message.id, "message-1")
        XCTAssertEqual(detail.message.body, "Ship it?")
        XCTAssertEqual(detail.message.options, ["Approve", "Wait"])
        XCTAssertEqual(detail.replies, [])
    }

    func testRejectsMalformedNotificationMessage() {
        XCTAssertNil(PushMessageSnapshot.decode(from: ["message": ["id": "message-1"]]))
    }

    @MainActor
    func testRouterCarriesMatchingSnapshotUntilNavigationFinishes() throws {
        let detail = try XCTUnwrap(PushMessageSnapshot.decode(from: Self.makeUserInfo()))
        AppRouter.shared.open(messageID: "message-1", cachedDetail: detail)

        XCTAssertEqual(AppRouter.shared.pendingMessage?.cachedDetail, detail)
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
