// MessageMeta density tests: selected names type/priority and adds channel/files.
// Exports: MessageMetaTests covering the shared catalog.
// Dependencies: XCTest, HiBoss app target, HibossKit.

import HibossKit
import XCTest
@testable import HiBoss

final class MessageMetaTests: XCTestCase {
    func testKnownPlatformChannelNamesPreserveBrandCasing() {
        let names = ["ios": "iOS", "ipados": "iPadOS", "macos": "macOS", "watchos": "watchOS",
                     "cli": "CLI", "web": "Web", "api": "API", "telegram": "Telegram",
                     "discord": "Discord", "custom_source": "Custom_Source"]
        for (raw, expected) in names {
            let message = HistoryMessage(id: "platform", body: "hello", direction: "agent_to_boss",
                                         status: "delivered", priority: "normal", channel: raw,
                                         createdAt: "")
            XCTAssertEqual(MessageMeta.items(for: message, density: .detail)
                .first { $0.id == "channel" }?.value, expected)
        }
    }

    func testSourceAndChannelUseTheSameCaseInsensitivePlatformNames() {
        for (raw, expected) in [("IOS", "iOS"), ("macOS", "macOS"), ("ipados", "iPadOS"),
                                ("watchos", "watchOS"), ("CLI", "CLI"), ("web", "Web"), ("api", "API"),
                                ("telegram", "Telegram"), ("discord", "Discord"),
                                ("other", "Other")] {
            XCTAssertEqual(AnswerSource.label(raw), expected)
            XCTAssertEqual(DecisionSettlement(answer: "Yes", source: raw).sourceLabel, expected)
            let device = AnsweringDevice(clientID: "test", kind: raw, label: " ")
            XCTAssertEqual(DecisionSettlement(answer: "Yes", source: nil, answeredBy: device).sourceLabel,
                           expected)
        }
    }

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
