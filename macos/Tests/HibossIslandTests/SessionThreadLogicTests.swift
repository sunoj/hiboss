// Session thread ordering, grouping, and reaction presentation regressions.
// Exports: SessionThreadLogicTests; deterministic dates keep refresh checks reproducible.
// Dependencies: XCTest, HibossKit, and SessionThreadLogic.

import HibossKit
import XCTest
@testable import HibossIsland

final class SessionThreadLogicTests: XCTestCase {
    private let now = ISODate.parse("2026-10-15T12:00:00Z")!

    func testScopedSessionDisplaysFollowupActivityBeforeNewerRoot() {
        let root = message("root", minute: 0)
        let newer = message("newer", minute: 10, agent: "Other")
        let followup = message("followup", minute: 20, parent: "root")
        let snapshot = OverviewSnapshot(history: [newer, root, followup], live: nil, now: now)
        let scoped = HistoryMessageLogic.scopedThreads(snapshot: snapshot, scope: .session("session"))
        let value = SessionThreadLogic(threads: scoped, answerability: snapshot.answerability, now: now)
        XCTAssertEqual(value.conversation.map(\.id), [root.id, newer.id])
    }

    func testEntriesAndReactionsMoveThreadByLastActivity() {
        let root = message("root", minute: 0)
        let entry = message("follow", minute: 20, parent: "root")
        let reacted = message("reacted", minute: 5, metadata: MessageMetadata(options: [], reactions: [
            MessageReaction(emoji: "👍", actor: .boss, actorID: "boss", createdAt: stamp(30))
        ]))
        let value = presentation([root, entry, reacted])
        XCTAssertEqual(value.conversation.map(\.id), [reacted.id, root.id])
        XCTAssertEqual(value.conversation.last?.threads.first?.entries.map(\.id), [entry.id])
    }

    func testNeedsYouUsesDeadlineThenOldestAndRemovesAnswered() {
        let old = decision("old", minute: 0)
        let soon = decision("soon", minute: 10, deadline: 70)
        let later = decision("later", minute: 5, deadline: 80)
        let answered = decision("answered", minute: 2, deadline: 65)
        let reply = message("reply", minute: 3, parent: "answered", boss: true)
        let value = presentation([later, old, soon, answered, reply], open: [old, soon, later, answered])
        XCTAssertEqual(value.needsYou.map(\.id), [soon.id, later.id, old.id])
        XCTAssertEqual(value.conversation.map(\.id), [answered.id])
        XCTAssertTrue(presentation([soon]).needsYou.isEmpty)
    }

    func testConsecutiveUpdatesMergeAtInclusiveTenMinuteWindowChronologically() {
        let a = message("a", minute: 0)
        let b = message("b", minute: 10)
        let c = message("c", minute: 19)
        let outside = message("outside", minute: 30)
        let value = presentation([c, outside, b, a])
        XCTAssertEqual(value.conversation.count, 2)
        XCTAssertEqual(value.conversation.last?.threads.map(\.id), [a.id, b.id, c.id])
    }

    func testOtherAgentsDecisionsAndEntriesBreakMerging() {
        let a = message("a", minute: 0)
        let other = message("other", minute: 1, agent: "Other")
        let b = message("b", minute: 2)
        let decision = decision("decision", minute: 3)
        let c = message("c", minute: 4)
        let entry = message("entry", minute: 5, parent: "c")
        XCTAssertEqual(presentation([a, other, b, decision, c, entry]).conversation.count, 5)
    }

    func testIdenticalRefreshAndEqualTimestampsKeepDeterministicIdentity() {
        let a = message("a", minute: 0, agent: "One")
        let b = message("b", minute: 0, agent: "Two")
        XCTAssertEqual(presentation([a, b]).conversation.map(\.id),
                       presentation([b, a]).conversation.map(\.id))
    }

    func testReactionChipsCountOnlyAndNameEmojiAccessibly() {
        let metadata = MessageMetadata(options: [], reactions: [
            MessageReaction(emoji: "👍", actor: .boss, actorID: "one", createdAt: stamp(0)),
            MessageReaction(emoji: "👍", actor: .agent, actorID: "two", createdAt: stamp(1)),
            MessageReaction(emoji: "🎉", actor: .boss, actorID: "one", createdAt: stamp(2))
        ])
        let chips = SessionThreadLogic.reactionChips(message("a", minute: 0, metadata: metadata))
        XCTAssertEqual(chips.map(\.text), ["👍 2", "🎉"])
        XCTAssertEqual(chips.map(\.accessibilityLabel), ["👍, 2", "🎉, 1"])
    }

    func testDaySeparatorsUseActivityAndDetailsRequireHiddenFiles() {
        let message = message("a", minute: 0)
        XCTAssertEqual(SessionThreadLogic.dayTitle(now, now: now), L("Today"))
        XCTAssertEqual(SessionThreadLogic.dayTitle(now.addingTimeInterval(-86400), now: now), L("Yesterday"))
        XCTAssertFalse(SessionThreadLogic.hasDetails(message))
        XCTAssertTrue(SessionThreadLogic.hasDetails(self.message("files", minute: 0,
            metadata: MessageMetadata(options: [], files: ["report.md"]))))
    }

    func testActivityGroupsCrossDayFollowupsAndLegacyReactionsDoNotInventDates() throws {
        let legacy = try JSONDecoder().decode(MessageMetadata.self,
            from: Data(#"{"reactions":[{"emoji":"👍","boss_id":"one"}]}"#.utf8))
        let old = message("old", minute: -1500, metadata: legacy)
        let recent = message("recent", minute: 0, agent: "Other")
        let followup = message("follow", minute: 1, parent: "old")
        let before = presentation([old, recent])
        XCTAssertEqual(before.days().count, 2)
        XCTAssertEqual(SessionThreadLogic.lastActivity(MessageThread(message: old)),
                       ISODate.parse(old.createdAt))
        let after = presentation([old, recent, followup])
        XCTAssertEqual(after.days().count, 1)
        XCTAssertEqual(after.days().first?.cards.map(\.id), [old.id, recent.id])
        XCTAssertFalse(SessionThreadLogic.hasDetails(message("content", minute: 0,
            metadata: MessageMetadata(options: [], content: "Visible content"))))
    }

    func testNeedsYouEqualDeadlinesUseOldestAndClosedOrExpiredCannotPin() {
        let old = decision("old", minute: 0, deadline: 80)
        let newer = decision("new", minute: 1, deadline: 80)
        let expired = decision("expired", minute: 0, deadline: 30)
        let closed = decision("closed", minute: 0)
        XCTAssertEqual(presentation([newer, closed, expired, old], open: [old, newer, expired])
            .needsYou.map(\.id), [old.id, newer.id])
    }

    func testRecordedReplyClosesControlsEvenWhenRequiredInputSnapshotStillListsDecision() {
        let root = decision("root", minute: 0)
        let reply = message("reply", minute: 1, parent: "root", boss: true)
        let thread = MessageThread(message: root, replies: [reply])
        let stale = AnswerableDecisions(isLoaded: true, openIDs: [root.id])
        let closed = SessionThreadLogic.answerability(for: thread, from: stale)
        XCTAssertEqual(closed.state(for: root.id), .closed)
        XCTAssertEqual(SessionThreadLogic.answerability(for: MessageThread(message: root), from: stale)
            .state(for: root.id), .open)
    }

    private func presentation(_ messages: [HistoryMessage],
                              open: [HistoryMessage] = []) -> SessionThreadLogic {
        SessionThreadLogic(threads: MessageThread.fold(messages),
            answerability: AnswerableDecisions(isLoaded: true, openIDs: Set(open.map(\.id))), now: now)
    }

    private func stamp(_ minute: Int) -> String {
        AttentionTestSupport.iso(now.addingTimeInterval(Double(minute - 60) * 60))
    }

    private func decision(_ id: String, minute: Int, deadline: Int? = nil) -> HistoryMessage {
        message(id, minute: minute, metadata: MessageMetadata(options: ["Ship", "Wait"]), deadline: deadline)
    }

    private func message(_ id: String, minute: Int, parent: String? = nil, boss: Bool = false,
                         agent: String = "Agent", metadata: MessageMetadata? = nil,
                         deadline: Int? = nil) -> HistoryMessage {
        HistoryMessage(id: MessageID(rawValue: id), body: id, agentName: agent,
            direction: boss ? "boss_to_agent" : "agent_to_boss", status: "delivered", priority: "normal",
            replyTo: parent, metadata: metadata, expiresAt: deadline.map(stamp),
            createdAt: stamp(minute), sessionId: "session")
    }
}
