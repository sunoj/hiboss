// MessageMeta density tests: selected names type/priority and adds channel/files.
// Exports: MessageMetaTests covering the shared catalog.
// Dependencies: XCTest, HiBoss app target, HibossKit.

import HibossKit
import XCTest
@testable import HiBoss

final class MessageMetaTests: XCTestCase {
    func testSelectedAlwaysNamesTypeAndPriority() {
        let ids = MessageMeta.items(for: Self.text, density: .selected).map(\.id)
        XCTAssertEqual(ids, ["type", "priority"])
    }

    func testSelectedAddsChannelAndFiles() {
        let items = MessageMeta.items(for: Self.ask, density: .selected)
        XCTAssertEqual(items.map(\.id), ["type", "priority", "mode", "channel", "files"])
        XCTAssertEqual(items.first { $0.id == "files" }?.value, String(localized: "\(2) files"))
        XCTAssertEqual(MessageMeta.typeGlyph("task_update").label, String(localized: "Update"))
    }

    private static let text = HistoryMessage(
        id: "t", body: "hello", direction: "agent_to_boss",
        status: "delivered", priority: "normal",
        createdAt: "2026-08-14T10:00:00Z"
    )

    private static let ask = HistoryMessage(
        id: "a", body: "Ship?", direction: "agent_to_boss",
        status: "delivered", priority: "critical",
        channel: "discord", mode: "blocking", type: "approval_request",
        metadata: MessageMetadata(options: ["Approve"], files: ["a.swift", "b.swift"]),
        createdAt: "2026-08-14T10:00:00Z"
    )
}
