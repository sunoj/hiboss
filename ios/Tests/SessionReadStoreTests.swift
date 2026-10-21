// Tests local unread predicates, account isolation, read watermarks and bounded retention.
// Exports SessionReadStoreTests using isolated UserDefaults and synthetic credentials.
// Dependencies: XCTest, HibossKit and the HiBoss app's session read state.

import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class SessionReadStoreTests: XCTestCase {
    private let baseline = Date(timeIntervalSince1970: 1_700_000_000)
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "SessionReadStoreTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testBaselineAndLastReadAreStrictCutoffs() {
        XCTAssertFalse(unread([message(at: baseline.addingTimeInterval(-1))]))
        XCTAssertFalse(unread([message(at: baseline)]))
        let new = message(at: baseline.addingTimeInterval(1))
        XCTAssertTrue(unread([new]))
        XCTAssertFalse(unread([new], lastRead: baseline.addingTimeInterval(1)))
        XCTAssertTrue(unread([new], lastRead: baseline.addingTimeInterval(-10)))
    }

    func testOnlyAgentMessagesInTheSameSessionCount() {
        let date = baseline.addingTimeInterval(1)
        XCTAssertFalse(unread([message(at: date, direction: " BOSS_TO_AGENT ")]))
        XCTAssertFalse(unread([message(at: date, direction: "unknown")]))
        XCTAssertFalse(unread([message(at: date, session: "other")]))
        XCTAssertTrue(unread([message(at: date, direction: " AGENT_TO_BOSS ")]))
        let malformed = HistoryMessage(id: "bad", body: "Update", direction: "agent_to_boss",
            status: "delivered", priority: "normal", createdAt: "invalid", sessionId: "session")
        XCTAssertFalse(unread([malformed]))
    }

    func testNeedsYouTakesPriorityOverUnread() {
        XCTAssertEqual(SessionIndicatorState(needsYou: true, unread: true), .needsYou)
        XCTAssertEqual(SessionIndicatorState(needsYou: true, unread: false), .needsYou)
        XCTAssertEqual(SessionIndicatorState(needsYou: false, unread: true), .unread)
        XCTAssertEqual(SessionIndicatorState(needsYou: false, unread: false), .none)
    }

    func testFirstAccountBaselinePersistsWithoutLightingOldHistory() {
        let account = account()
        let store = SessionReadStore(defaults: defaults)
        store.activate(account, now: baseline)
        XCTAssertTrue(store.unreadSessionIDs(messages: [message(at: baseline)]).isEmpty)
        let restored = SessionReadStore(defaults: defaults)
        restored.activate(account, now: baseline.addingTimeInterval(100))
        XCTAssertEqual(restored.baseline, baseline)
        XCTAssertEqual(restored.unreadSessionIDs(messages: [message(at: baseline.addingTimeInterval(1))]),
                       ["session"])
    }

    func testServerAndTokenScopeReadsWithoutPersistingToken() {
        let first = account(token: "abc")
        let second = account(token: "def")
        let otherServer = account(server: "https://other.invalid", token: "abc")
        XCTAssertEqual(first.identity, "ba7816bf8f01cfea")
        XCTAssertEqual(first.identity.count, 16)
        XCTAssertNotEqual(first.storageKey, second.storageKey)
        XCTAssertNotEqual(first.storageKey, otherServer.storageKey)
        let store = SessionReadStore(defaults: defaults)
        store.activate(first, now: baseline)
        store.markRead("session", messages: [], now: baseline.addingTimeInterval(5))
        for next in [second, otherServer] {
            store.activate(next, now: baseline.addingTimeInterval(10))
            XCTAssertTrue(store.lastRead.isEmpty)
            XCTAssertEqual(store.baseline, baseline.addingTimeInterval(10))
        }
        store.activate(first, now: baseline.addingTimeInterval(20))
        XCTAssertEqual(store.lastRead["session"], baseline.addingTimeInterval(5))
        let record = String(data: defaults.data(forKey: first.storageKey)!, encoding: .utf8)!
        XCTAssertFalse(record.contains("abc"))
        store.activate(nil)
        XCTAssertTrue(store.lastRead.isEmpty)
        XCTAssertEqual(store.baseline, .distantFuture)
    }

    func testOpeningAndNewVisibleAgentArrivalClearUnread() {
        let store = SessionReadStore(defaults: defaults)
        store.activate(account(), now: baseline)
        let new = message(at: baseline.addingTimeInterval(10))
        XCTAssertEqual(store.unreadSessionIDs(messages: [new]), ["session"])
        store.markRead("session", messages: [new], now: baseline.addingTimeInterval(5))
        XCTAssertTrue(store.unreadSessionIDs(messages: [new]).isEmpty)
        let arrival = message(at: baseline.addingTimeInterval(20))
        XCTAssertEqual(store.unreadSessionIDs(messages: [arrival]), ["session"])
        store.markRead("session", messages: [arrival], now: baseline.addingTimeInterval(15))
        XCTAssertTrue(store.unreadSessionIDs(messages: [arrival]).isEmpty)
        store.markRead("session", messages: [], now: baseline)
        XCTAssertEqual(store.lastRead["session"], baseline.addingTimeInterval(20))
    }

    func testTranscriptArrivalAdvancesWatermarkBeforeHistoryCatchesUp() {
        let store = SessionReadStore(defaults: defaults)
        store.activate(account(), now: baseline)
        let agent = message(at: baseline.addingTimeInterval(20))
        store.markRead("session", messages: [],
                       events: DemoSessionStream.events(for: "session", from: [agent]),
                       now: baseline.addingTimeInterval(1))
        XCTAssertTrue(store.unreadSessionIDs(messages: [agent]).isEmpty)
        let boss = message(at: baseline.addingTimeInterval(100), direction: "boss_to_agent")
        store.markRead("session", messages: [boss],
                       events: DemoSessionStream.events(for: "session", from: [boss]),
                       now: baseline.addingTimeInterval(2))
        XCTAssertEqual(store.lastRead["session"], baseline.addingTimeInterval(20))
    }

    func testPrunesEntriesOlderThanThirtyDaysOnActivationAndRead() {
        let store = SessionReadStore(defaults: defaults)
        store.activate(account(), now: baseline)
        store.markRead("old", messages: [], now: baseline)
        let boundary = baseline.addingTimeInterval(30 * 24 * 60 * 60)
        let restored = SessionReadStore(defaults: defaults)
        restored.activate(account(), now: boundary)
        XCTAssertNotNil(restored.lastRead["old"])
        restored.markRead("new", messages: [], now: boundary.addingTimeInterval(1))
        XCTAssertNil(restored.lastRead["old"])
        XCTAssertNotNil(restored.lastRead["new"])
        let expired = SessionReadStore(defaults: defaults)
        expired.activate(account(), now: boundary.addingTimeInterval(30 * 24 * 60 * 60 + 2))
        XCTAssertTrue(expired.lastRead.isEmpty)
        XCTAssertEqual(expired.baseline, baseline)
    }

    func testPrunesToFiveHundredMostRecentSessions() {
        let store = SessionReadStore(defaults: defaults)
        store.activate(account(), now: baseline)
        for index in 0...500 {
            store.markRead("session-\(index)", messages: [], now: baseline.addingTimeInterval(Double(index)))
        }
        XCTAssertEqual(store.lastRead.count, 500)
        XCTAssertNil(store.lastRead["session-0"])
        XCTAssertNotNil(store.lastRead["session-500"])
        let restored = SessionReadStore(defaults: defaults)
        restored.activate(account(), now: baseline.addingTimeInterval(501))
        XCTAssertEqual(restored.lastRead, store.lastRead)
    }

    private func account(
        server: String = "https://test.invalid", token: String = "abc"
    ) -> SessionReadAccount {
        SessionReadAccount(config: ConnectionConfig(serverURL: URL(string: server)!, bossToken: token))
    }

    private func message(at date: Date, direction: String = "agent_to_boss",
                         session: String = "session") -> HistoryMessage {
        HistoryMessage(id: "update", body: "Update", direction: direction, status: "delivered",
                       priority: "normal", createdAt: date.ISO8601Format(), sessionId: session)
    }

    private func unread(_ messages: [HistoryMessage], lastRead: Date? = nil) -> Bool {
        SessionUnread.isUnread(sessionID: "session", messages: messages, lastRead: lastRead, baseline: baseline)
    }
}
