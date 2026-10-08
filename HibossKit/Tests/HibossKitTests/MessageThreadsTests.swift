// Shared history fold and outcome coverage, including automatic-answer provenance.
// Exports: MessageThreadsTests for both native clients' thread contract.
// Dependencies: XCTest, Foundation and HibossKit.

import Foundation
import HibossKit
import XCTest

final class MessageThreadsTests: XCTestCase {
    func testOpenDecisionAndElapsedDeadline() {
        let message = question(expiresAt: "2026-10-08T12:00:00Z")
        let thread = MessageThread(message: message)
        XCTAssertEqual(thread.outcome(at: Date(timeIntervalSince1970: 0)), .open)
        XCTAssertEqual(thread.outcome(at: Date(timeIntervalSince1970: 4_000_000_000)), .expired)
    }

    func testChosenOptionAndSource() {
        let thread = MessageThread(message: question(), replies: [reply("r", body: "Ship")])
        XCTAssertEqual(thread.outcome, .chosen(option: "Ship", source: "telegram"))
    }

    func testAutomaticReplyNeverBecomesABossChoice() {
        let answer = reply("r", body: "Hold", autoDefault: true)
        let thread = MessageThread(message: question(), replies: [answer])
        XCTAssertEqual(thread.outcome, .autoSelected(option: "Hold"))
        XCTAssertEqual(ThreadOutcome(reply: answer), .autoSelected(option: "Hold"))
    }

    func testParentOptionsExpiredOverridesUnmarkedReply() {
        let thread = MessageThread(message: question(optionsExpired: true),
                                   replies: [reply("r", body: "Hold")])
        XCTAssertEqual(thread.outcome, .autoSelected(option: "Hold"))
    }

    func testParentOptionsExpiredWithoutReplyUsesOnlyRecordedDefault() {
        let message = question(optionsExpired: true, defaultOption: " Hold ")
        XCTAssertEqual(MessageThread(message: message).outcome, .autoSelected(option: "Hold"))
        XCTAssertEqual(MessageThread(message: question(optionsExpired: true)).outcome,
                       .autoSelected(option: nil))
    }

    func testReplyMatchingNoOptionIsFreeTextAndDoesNotGuess() {
        let thread = MessageThread(message: question(), replies: [reply("r", body: " ship ")])
        XCTAssertEqual(thread.outcome, .replied(text: "ship", source: "telegram"))
    }

    func testExpiredWithoutReply() {
        XCTAssertEqual(MessageThread(message: question(status: "expired")).outcome, .expired)
    }

    func testResolvedParentWithoutLoadedReplyDoesNotInventAnAnswerOrExpiry() {
        XCTAssertEqual(MessageThread(message: question(status: "replied")).outcome, .none)
    }

    func testNoOptionsKeepsNestedRepliesWithoutADecisionOutcome() {
        let message = question(options: [])
        let answer = reply("r", body: "Thanks")
        let threads = MessageThread.fold([message, answer])
        XCTAssertEqual(threads, [MessageThread(message: message, replies: [answer])])
        XCTAssertEqual(threads.first?.outcome, ThreadOutcome.none)
    }

    func testMultipleRepliesKeepServerOrderAndNewestTimestampDecides() {
        let message = question()
        let early = reply("early", body: "Hold", at: "2026-10-08T10:01:00Z")
        let late = reply("late", body: "Ship", at: "2026-10-08T10:02:00Z")
        for replies in [[late, early], [early, late]] {
            let threads = MessageThread.fold([replies[0], message, replies[1]])
            XCTAssertEqual(threads, [MessageThread(message: message, replies: replies)])
            XCTAssertEqual(threads.first?.newestReply, late)
            XCTAssertEqual(threads.first?.outcome, .chosen(option: "Ship", source: "telegram"))
        }
    }

    func testNewestAutomaticReplyOverridesEarlierBossChoice() {
        let early = reply("early", body: "Ship", at: "2026-10-08T10:01:00Z")
        let late = reply("late", body: "Hold", autoDefault: true, at: "2026-10-08T10:02:00Z")
        let thread = MessageThread.fold([late, question(), early]).first
        XCTAssertEqual(thread?.replies, [late, early])
        XCTAssertEqual(thread?.outcome, .autoSelected(option: "Hold"))
    }

    func testNewestReplyAcceptsSQLiteAndMixedTimestampFormats() {
        let sql = reply("sql", body: "Hold", at: "2026-10-08 10:03:00")
        for date in ["2026-10-08 10:01:00", "2026-10-08T10:01:00Z"] {
            let earlier = reply("early", body: "Ship", at: date)
            let thread = MessageThread(message: question(), replies: [earlier, sql])
            XCTAssertEqual(thread.newestReply, sql)
            XCTAssertEqual(thread.outcome, .chosen(option: "Hold", source: "telegram"))
        }
    }

    func testUnlinkedBossMessagesStayStandaloneAndKeepRowOrder() {
        let orphan = reply("orphan", body: "Hold", parent: "missing")
        let standalone = reply("standalone", body: "Pause", parent: nil)
        let message = question()
        let threads = MessageThread.fold([orphan, message, standalone])
        XCTAssertEqual(threads.map(\.id), [orphan.id, message.id, standalone.id])
        XCTAssertTrue(threads[0].isBoss)
        XCTAssertEqual(threads[0].outcome, .none)
        XCTAssertEqual(threads[0].replies, [])
        XCTAssertEqual(orphan.agentName, message.agentName)
    }

    func testOnlyBossRepliesLinkToAgentParents() {
        let boss = reply("boss", body: "Pause", parent: nil)
        let bossChild = reply("boss-child", body: "Again", parent: "boss")
        let agent = HistoryMessage(id: "agent", body: "Update", direction: "agent_to_boss",
                                   status: "sent", priority: "normal", replyTo: "q", createdAt: "invalid")
        let threads = MessageThread.fold([question(), boss, bossChild, agent])
        XCTAssertEqual(threads.map(\.id), ["q", "boss", "boss-child", "agent"])
        XCTAssertTrue(threads.allSatisfy { $0.replies.isEmpty })
    }

    func testOptionAndReplyWhitespaceIsTrimmedBeforeExactMatching() {
        let thread = MessageThread(message: question(options: ["\n Ship \t", "Hold"]),
                                   replies: [reply("r", body: "\tShip\n")])
        XCTAssertEqual(thread.outcome, .chosen(option: "Ship", source: "telegram"))
    }

    func testDefaultEqualityAndSystemSourceDoNotImplyAutomaticChoice() {
        let answer = reply("r", body: "Hold", source: "system")
        let thread = MessageThread(message: question(defaultOption: "Hold"), replies: [answer])
        XCTAssertEqual(thread.outcome, .chosen(option: "Hold", source: "system"))
    }

    func testEqualOrInvalidTimestampsKeepFirstServerReply() {
        let first = reply("first", body: "Ship", at: "invalid")
        let second = reply("second", body: "Hold", at: "invalid")
        XCTAssertEqual(MessageThread(message: question(), replies: [first, second]).newestReply, first)
    }

    private func question(options: [String] = ["Ship", "Hold"], status: String = "delivered",
                          optionsExpired: Bool = false, defaultOption: String? = nil,
                          expiresAt: String? = nil) -> HistoryMessage {
        HistoryMessage(id: "q", body: "Ship?", agentName: "worker", direction: "agent_to_boss",
                       status: status, priority: "normal",
                       metadata: MessageMetadata(options: options, isExpired: optionsExpired,
                                                 defaultOption: defaultOption),
                       expiresAt: expiresAt, createdAt: "2026-10-08T10:00:00Z")
    }

    private func reply(_ id: String, body: String, parent: String? = "q", source: String = "telegram",
                       autoDefault: Bool = false, at: String = "2026-10-08T10:01:00Z") -> HistoryMessage {
        HistoryMessage(id: MessageID(rawValue: id), body: body, agentName: "worker",
                       direction: "boss_to_agent", status: "sent", priority: "normal", replyTo: parent,
                       metadata: MessageMetadata(options: [], source: source, isAutoDefault: autoDefault),
                       createdAt: at)
    }
}
