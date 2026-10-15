// Verifies session pinning, deterministic activity order and standalone update boundaries.
// Dependencies: XCTest, HibossKit and the app's pure SessionThreads presentation model.

import HibossKit
import XCTest
@testable import HiBoss

final class SessionThreadsTests: XCTestCase {
    func testFollowupAndReactionMoveWholeThreadWithoutChangingEntryOrder() {
        let root = message("root", at: 0, options: ["Ship", "Hold"])
        let reply = message("reply", at: 10, parent: "root", boss: true)
        let followup = message("followup", at: 20, parent: "reply", reactionAt: 100)
        let other = message("other", at: 90, agent: "other")
        let layout = SessionThreads(messages: [root, other, followup, reply], isOpen: { _ in true })
        XCTAssertTrue(layout.needsYou.isEmpty)
        XCTAssertEqual(layout.conversation.map(\.id.rawValue), ["root", "other"])
        XCTAssertEqual(layout.conversation[0].threads[0].entries.map(\.id.rawValue), ["reply", "followup"])
        XCTAssertEqual(layout.conversation[0].lastActivity, base.addingTimeInterval(100))
    }

    func testNeedsYouUsesDeadlineThenOldestAndExcludesAnsweredOrClosed() {
        let older = message("older", at: 0, options: ["Yes"], deadline: 800)
        let urgent = message("urgent", at: 20, options: ["Yes"], deadline: 700)
        let later = message("later", at: 30, options: ["Yes"], deadline: 800)
        let noDeadline = message("no-deadline", at: 0, options: ["Yes"])
        let closed = message("closed", at: 0, options: ["Yes"])
        let answered = message("answered", at: 0, options: ["Yes"])
        let reply = message("reply", at: 40, parent: "answered", boss: true)
        let layout = SessionThreads(messages: [later, closed, urgent, answered, noDeadline, reply, older],
                                    isOpen: { $0.rawValue != "closed" })
        XCTAssertEqual(layout.needsYou.map(\.id.rawValue), ["urgent", "older", "later", "no-deadline"])
        XCTAssertEqual(Set(layout.conversation.map(\.id.rawValue)), ["closed", "answered"])
    }

    func testEqualActivityAndIdenticalRefreshAreStableEvenWithReorderedInput() {
        let first = message("a", at: 0, agent: "a")
        let second = message("b", at: 0, agent: "b")
        let original = SessionThreads(messages: [second, first], isOpen: { _ in false })
        let refreshed = SessionThreads(messages: [first, second], isOpen: { _ in false })
        XCTAssertEqual(original.conversation, refreshed.conversation)
        XCTAssertEqual(original.conversation.map(\.id.rawValue), ["a", "b"])
    }

    func testConsecutiveUpdatesMergeAtTenMinutesButDecisionsAndOtherAgentsBreakRuns() {
        let first = message("a", at: 0)
        let second = message("b", at: 600)
        let third = message("c", at: 1201)
        let decision = message("d", at: 1250, options: ["Yes"])
        let fourth = message("e", at: 1300)
        let other = message("f", at: 1350, agent: "other")
        let fifth = message("g", at: 1400)
        let cards = SessionThreads(messages: [first, second, third, decision, fourth, other, fifth],
                                   isOpen: { _ in true }).conversation
        XCTAssertEqual(cards.map { $0.threads.map(\.id.rawValue) }, [["g"], ["f"], ["e"], ["c"], ["a", "b"]])
    }

    func testDetailsRequireEvidenceBeyondVisibleBody() {
        XCTAssertFalse(SessionThreads.hasDetails(message("a", at: 0)))
        let repeated = MessageMetadata(options: [], content: "Body")
        XCTAssertFalse(SessionThreads.hasDetails(message("b", at: 0, metadata: repeated)))
        let content = MessageMetadata(options: [], content: "More context")
        XCTAssertTrue(SessionThreads.hasDetails(message("c", at: 0, metadata: content)))
        let files = MessageMetadata(options: [], files: ["report.md"])
        XCTAssertTrue(SessionThreads.hasDetails(message("d", at: 0, metadata: files)))
        let inlineImage = MessageMetadata(options: [], fileURL: "https://example.com/image.png")
        XCTAssertFalse(SessionThreads.hasDetails(message("e", at: 0, metadata: inlineImage)))
    }

    func testLiveMessagesJoinHistoryWithoutDuplicatesAndKeepAncestry() {
        let root = message("root", at: 0)
        let event = SessionEvent(id: "event", sessionId: "session", sequence: 1, kind: "message",
                                 direction: "agent_to_boss", actorName: "agent", messageId: "entry",
                                 payload: .object(["body": .string("Followup"), "reply_to": .string("root")]),
                                 createdAt: base.addingTimeInterval(10).ISO8601Format())
        let joined = SessionThreadMessages.messages(
            sessionID: "session", history: [root], events: [event, event])
        XCTAssertEqual(joined.count, 2)
        XCTAssertEqual(MessageThread.fold(joined).first?.entries.map(\.id.rawValue), ["entry"])
    }

    func testUnscopedRepliesStayWithTheirLoadedSessionRoot() {
        let root = message("root", at: 0)
        let reply = HistoryMessage(id: "reply", body: "Yes", direction: "boss_to_agent",
                                   status: "sent", priority: "normal", replyTo: "root",
                                   createdAt: base.addingTimeInterval(10).ISO8601Format())
        let joined = SessionThreadMessages.messages(
            sessionID: "session", history: [reply, root], events: [])
        XCTAssertEqual(joined.map(\.id.rawValue), ["root", "reply"])
    }

    func testBlockingTextDecisionIsPinnedUntilAnswered() {
        let ask = HistoryMessage(id: "ask", body: "Which name?", direction: "agent_to_boss",
                                 status: "delivered", priority: "normal", mode: "blocking",
                                 createdAt: base.ISO8601Format(), sessionId: "session")
        let pinned = SessionThreads(messages: [ask], isOpen: { _ in true })
        XCTAssertEqual(pinned.needsYou.map(\.id), [ask.id])
        XCTAssertTrue(SessionThreads(messages: [ask], isOpen: { _ in false }).needsYou.isEmpty)
    }

    private let base = Date(timeIntervalSince1970: 2_000_000_000)

    private func message(_ id: String, at seconds: TimeInterval, parent: String? = nil,
                         boss: Bool = false, agent: String = "agent", options: [String] = [],
                         deadline: TimeInterval? = nil, reactionAt: TimeInterval? = nil,
                         metadata: MessageMetadata? = nil) -> HistoryMessage {
        let reactions = reactionAt.map {
            [MessageReaction(emoji: "👍", actor: .boss, actorID: "boss",
                             createdAt: base.addingTimeInterval($0).ISO8601Format())]
        } ?? []
        return HistoryMessage(id: MessageID(rawValue: id), body: "Body", agentName: agent,
                              direction: boss ? "boss_to_agent" : "agent_to_boss", status: "delivered",
                              priority: "normal", replyTo: parent,
                              metadata: metadata ?? MessageMetadata(options: options, reactions: reactions),
                              expiresAt: deadline.map { base.addingTimeInterval($0).ISO8601Format() },
                              createdAt: base.addingTimeInterval(seconds).ISO8601Format(), sessionId: "session")
    }
}
