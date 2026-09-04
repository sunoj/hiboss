// Unit tests for macOS History filtering and presentation helpers.
// Covers: segments, search, unread counts, monograms, and timestamp formatting.
// Dependencies: XCTest, HibossKit HistoryMessage fixtures, and HibossIsland logic.

import HibossKit
import XCTest
@testable import HibossIsland

final class HistoryLogicTests: XCTestCase {
    func testAllSegmentIncludesEveryHistoryMessage() {
        let delivered = historyMessage(id: "delivered", status: "delivered")
        let replied = historyMessage(id: "replied", status: "replied")

        XCTAssertTrue(HistorySegment.all.includes(delivered))
        XCTAssertTrue(HistorySegment.all.includes(replied))
    }

    func testUnreadSegmentIncludesDeliveredAndUnreadOnly() {
        let delivered = historyMessage(id: "delivered", status: "delivered")
        let unread = historyMessage(id: "unread", status: "unread")
        let read = historyMessage(id: "read", status: "read")
        let replied = historyMessage(id: "replied", status: "replied")

        XCTAssertTrue(HistorySegment.unread.includes(delivered))
        XCTAssertTrue(HistorySegment.unread.includes(unread))
        XCTAssertFalse(HistorySegment.unread.includes(read))
        XCTAssertFalse(HistorySegment.unread.includes(replied))
    }

    func testBlockingSegmentRequiresActiveOptionsAndUnresolvedStatus() {
        let active = historyMessage(
            id: "active",
            status: "read",
            options: ["Approve", "Wait"]
        )
        let deliveredWithoutOptions = historyMessage(id: "plain", status: "delivered")
        let repliedWithOptions = historyMessage(
            id: "replied",
            status: "replied",
            options: ["Approve"]
        )
        let expiredMetadata = historyMessage(
            id: "expired",
            status: "delivered",
            options: ["Approve"],
            isExpired: true
        )

        XCTAssertTrue(HistorySegment.blocking.includes(active))
        XCTAssertFalse(HistorySegment.blocking.includes(deliveredWithoutOptions))
        XCTAssertFalse(HistorySegment.blocking.includes(repliedWithOptions))
        XCTAssertFalse(HistorySegment.blocking.includes(expiredMetadata))
    }

    func testUnreadCountAndSegmentTitleStayLive() {
        let messages = [
            historyMessage(id: "one", status: "delivered"),
            historyMessage(id: "two", status: "unread"),
            historyMessage(id: "three", status: "read"),
        ]

        let count = HistoryMessageLogic.unreadCount(in: messages)

        XCTAssertEqual(count, 2)
        XCTAssertEqual(HistorySegment.unread.title(unreadCount: count), L("Unread \(count)"))
    }

    func testSearchMatchesAcrossBodyAgentChannelModeAndOptions() {
        let message = historyMessage(
            id: "searchable",
            body: "Deployment needs approval",
            agentName: "Build Agent",
            channel: "discord",
            mode: "blocking",
            options: ["Ship safely", "Wait"]
        )

        XCTAssertTrue(message.matchesHistorySearch("build discord"))
        XCTAssertTrue(message.matchesHistorySearch("safely"))
        XCTAssertTrue(message.matchesHistorySearch("deployment blocking"))
        XCTAssertFalse(message.matchesHistorySearch("telegram"))
    }

    func testFilteredMessagesCombineSegmentAndSearch() {
        let matching = historyMessage(
            id: "matching",
            body: "Release approval",
            status: "delivered",
            options: ["Ship"]
        )
        let wrongSearch = historyMessage(
            id: "wrong-search",
            body: "Database backup",
            status: "delivered",
            options: ["Ship"]
        )
        let resolved = historyMessage(
            id: "resolved",
            body: "Release approval",
            status: "replied",
            options: ["Ship"]
        )

        let result = HistoryMessageLogic.filtered(
            [matching, wrongSearch, resolved],
            segment: .blocking,
            searchText: "release"
        )

        XCTAssertEqual(result.map(\.id), [matching.id])
    }

    func testHistoryDetailsRequireDoubleClick() {
        XCTAssertEqual(HistoryMessageLogic.detailClickCount, 2)
    }

    func testHistoryPreviewReservesDoubleClickForOpeningDetails() {
        XCTAssertFalse(HistoryMessageLogic.allowsPreviewTextSelection)
    }

    func testHistoryDetailPrioritizesMessageOverSupportingMetadata() {
        XCTAssertEqual(
            HistoryDetailLayout.sections(hasChoices: true),
            [.message, .choices, .metadata]
        )
        XCTAssertEqual(
            HistoryDetailLayout.sections(hasChoices: false),
            [.message, .metadata]
        )
        XCTAssertFalse(HistoryDetailLayout.showsMetadataByDefault)
    }

    func testMonogramDerivesFromAgentNameAndBossMessages() {
        XCTAssertEqual(HistoryMessage.monogram(agentName: "Build Agent", isBossMessage: false), "BA")
        XCTAssertEqual(HistoryMessage.monogram(agentName: "qa-bot", isBossMessage: false), "QB")
        XCTAssertEqual(HistoryMessage.monogram(agentName: nil, isBossMessage: false), String(L("Agent").prefix(2)).uppercased())
        XCTAssertEqual(HistoryMessage.monogram(agentName: "Build Agent", isBossMessage: true), L("Me"))
    }

    func testTimestampParsesServerStringsAndFormatsShortLocalTime() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Bangkok"))
        let locale = Locale(identifier: "en_US_POSIX")
        let formatted = HistoryTimestamp.shortLocalTime(
            from: "2026-07-15 10:00:00",
            locale: locale,
            timeZone: timeZone
        )

        XCTAssertNotNil(HistoryTimestamp.date(from: "2026-07-15T10:00:00.123Z"))
        XCTAssertEqual(
            formatted.replacingOccurrences(of: "\u{202F}", with: " "),
            "5:00 PM"
        )
        XCTAssertEqual(HistoryTimestamp.shortLocalTime(from: "not-a-date"), L("Unknown"))
    }

    func testPresentationFieldsComeFromHistoryModel() {
        let bossMessage = historyMessage(
            id: "boss",
            direction: "boss_to_agent",
            status: "replied",
            priority: "high",
            mode: "window"
        )
        let peerMessage = historyMessage(id: "peer", direction: "agent_to_agent")

        XCTAssertEqual(bossMessage.historyDisplayName, L("Me"))
        XCTAssertEqual(bossMessage.historyMonogram, L("Me"))
        XCTAssertEqual(bossMessage.historyDirectionGlyph, "arrow.left")
        XCTAssertEqual(bossMessage.historyDirectionAccessibilityLabel, L("From boss"))
        XCTAssertEqual(bossMessage.historyPriorityGlyph, "exclamationmark.triangle.fill")
        XCTAssertEqual(bossMessage.historyPriorityAccessibilityLabel, L("\(L("High")) priority"))
        XCTAssertEqual(bossMessage.historyPriorityModeLabel, "HIGH · WINDOW")
        XCTAssertEqual(bossMessage.historyStatusChip, L("✓ replied"))
        XCTAssertEqual(peerMessage.historyDirectionGlyph, "arrow.left.arrow.right")
        XCTAssertEqual(peerMessage.historyDirectionAccessibilityLabel, L("Peer message"))
        // Normal priority draws no glyph at all — a symbol on every row is noise.
        XCTAssertNil(peerMessage.historyPriorityGlyph)
    }

    func testGroupBySessionOrdersByNewestAndBucketsDirect() {
        let olderSession = historyMessage(
            id: "a1",
            createdAt: "2026-07-15 09:00:00",
            sessionId: "sess-old",
            sessionLabel: "Older Work",
            sessionStatus: "idle"
        )
        let newerSession = historyMessage(
            id: "b1",
            createdAt: "2026-07-15 12:00:00",
            sessionId: "sess-new",
            sessionLabel: "Newer Work",
            sessionStatus: "working"
        )
        let directOlder = historyMessage(
            id: "d1",
            createdAt: "2026-07-15 10:00:00",
            sessionId: nil
        )
        let directNewer = historyMessage(
            id: "d2",
            createdAt: "2026-07-15 11:00:00",
            sessionId: nil
        )

        let groups = HistoryMessageLogic.groupBySession([
            olderSession, directOlder, newerSession, directNewer,
        ])

        XCTAssertEqual(groups.map(\.id), ["sess-new", HistoryMessageLogic.directSessionID, "sess-old"])
        XCTAssertEqual(groups[0].label, "Newer Work")
        XCTAssertEqual(groups[1].label, "Direct")
        XCTAssertEqual(groups[1].messages.map(\.id), [directOlder.id, directNewer.id])
        XCTAssertTrue(groups[0].isExpandedByDefault)
        XCTAssertFalse(groups[2].isExpandedByDefault)
    }

    func testGroupBySessionFallsBackThroughLabelBranchAndShortID() {
        let labeled = historyMessage(
            id: "l1",
            createdAt: "2026-07-15 12:00:00",
            sessionId: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            sessionLabel: "Labeled",
            sessionBranch: "feat/ignored"
        )
        let branched = historyMessage(
            id: "br1",
            createdAt: "2026-07-15 11:00:00",
            sessionId: "11111111-2222-3333-4444-555555555555",
            sessionBranch: "feat/session-group"
        )
        let idOnly = historyMessage(
            id: "id1",
            createdAt: "2026-07-15 10:00:00",
            sessionId: "abcdef12-3456-7890-abcd-ef1234567890"
        )

        let groups = HistoryMessageLogic.groupBySession([labeled, branched, idOnly])

        XCTAssertEqual(groups.map(\.label), ["Labeled", "feat/session-group", "abcdef12"])
    }

    private func historyMessage(
        id: MessageID,
        body: String = "Message body",
        agentName: String? = "Test Agent",
        direction: String = "agent_to_boss",
        status: String = "delivered",
        priority: String = "normal",
        channel: String? = nil,
        mode: String? = nil,
        options: [String] = [],
        isExpired: Bool = false,
        createdAt: String = "2026-07-15 10:00:00",
        sessionId: String? = nil,
        sessionLabel: String? = nil,
        sessionBranch: String? = nil,
        sessionStatus: String? = nil
    ) -> HistoryMessage {
        HistoryMessage(
            id: id,
            body: body,
            agentName: agentName,
            direction: direction,
            status: status,
            priority: priority,
            channel: channel,
            mode: mode,
            metadata: options.isEmpty ? nil : MessageMetadata(options: options, isExpired: isExpired),
            createdAt: createdAt,
            sessionId: sessionId,
            sessionLabel: sessionLabel,
            sessionBranch: sessionBranch,
            sessionStatus: sessionStatus
        )
    }
}
