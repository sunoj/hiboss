// Verifies unread cutoffs, direction filtering, local account isolation, and bounded retention.
// Exports: SessionReadStoreTests using isolated preferences and deterministic timestamps.
// Dependencies: XCTest, HibossKit, and the macOS-only session read store.

import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class SessionReadStoreTests: XCTestCase {
    private let now = AttentionTestSupport.now

    func testAccountFingerprintIsSixteenHexCharactersAndContainsNoToken() {
        let url = URL(string: "https://unread.invalid")!
        let first = SessionReadAccount(config: ConnectionConfig(serverURL: url, bossToken: "abc"))
        XCTAssertEqual(first.identity, "ba7816bf8f01cfea")
        XCTAssertEqual(first.identity.count, 16)
        XCTAssertEqual(first, SessionReadAccount(config: ConnectionConfig(serverURL: url, bossToken: "abc")))
        XCTAssertNotEqual(first, SessionReadAccount(config: ConnectionConfig(serverURL: url, bossToken: "def")))
        let decoded = String(data: Data(base64Encoded: String(first.storageKey.split(separator: ".").last!))!,
            encoding: .utf8)!
        XCTAssertFalse(decoded.contains("abc"))
        XCTAssertTrue(decoded.contains(first.identity))
    }

    func testFirstAccountBaselineDoesNotMakeExistingMessagesUnread() throws {
        let (defaults, name) = preferences()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SessionReadStore(defaults: defaults)
        store.activate(account("one"), now: now)
        let snapshot = snapshot([message(at: -1), message(at: 0)])
        XCTAssertTrue(store.unreadSessionIDs(in: snapshot).isEmpty)
        XCTAssertEqual(store.baseline, now)
        let restored = SessionReadStore(defaults: defaults)
        restored.activate(account("one"), now: now.addingTimeInterval(10))
        XCTAssertEqual(restored.baseline, now)
        XCTAssertEqual(restored.unreadSessionIDs(in: self.snapshot([message(at: 1)])), ["session"])
    }

    func testAgentMessagesMustBeStrictlyNewerThanBaselineAndLastRead() throws {
        let snapshot = snapshot([message(at: 10)])
        let session = try XCTUnwrap(snapshot.today.sessionDirectory.working.first)
        XCTAssertTrue(isUnread(session: session, messages: snapshot.history, lastRead: nil, baseline: now))
        XCTAssertFalse(isUnread(session: session, messages: snapshot.history,
            lastRead: now.addingTimeInterval(10), baseline: now))
        XCTAssertTrue(isUnread(session: session, messages: snapshot.history,
            lastRead: now.addingTimeInterval(9), baseline: now))
        XCTAssertFalse(isUnread(session: session, messages: [message(at: -1)],
            lastRead: now.addingTimeInterval(-20), baseline: now))
    }

    func testBossRepliesOtherSessionsAndMalformedDatesDoNotMakeUnread() throws {
        let session = try XCTUnwrap(snapshot([message(at: 0)]).today.sessionDirectory.working.first)
        let malformed = HistoryMessage(id: "invalid", body: "No timestamp", direction: "agent_to_boss",
            status: "delivered", priority: "normal", createdAt: "invalid", sessionId: "session")
        XCTAssertFalse(isUnread(session: session,
            messages: [message(at: 10, direction: " BOSS_TO_AGENT \n"),
                message(at: 10, session: "other"), malformed], lastRead: nil, baseline: now))
        XCTAssertTrue(isUnread(session: session, messages: [message(at: 10, direction: "unknown")],
            lastRead: nil, baseline: now))
    }

    func testNeedsYouTakesPriorityAndReadIdleHasNoIndicatorLabel() {
        XCTAssertEqual(SidebarSessionIndicator(needsYou: true, unread: true), .needsYou)
        XCTAssertEqual(SidebarSessionIndicator(needsYou: true, unread: false).label, L("Needs You"))
        XCTAssertEqual(SidebarSessionIndicator(needsYou: false, unread: true).label, L("Unread"))
        XCTAssertEqual(SidebarSessionIndicator(needsYou: false, unread: false).label, "")
    }

    func testAccountsAndServersRestoreIndependentReadState() {
        let (defaults, name) = preferences()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SessionReadStore(defaults: defaults)
        store.activate(account("one"), now: now)
        store.markRead("session", messages: [], now: now.addingTimeInterval(10))
        store.activate(account("two"), now: now.addingTimeInterval(20))
        XCTAssertTrue(store.lastRead.isEmpty)
        store.markRead("other", messages: [], now: now.addingTimeInterval(30))
        store.activate(account("one", server: "https://other.invalid"), now: now.addingTimeInterval(40))
        XCTAssertTrue(store.lastRead.isEmpty)
        store.activate(account("one"), now: now.addingTimeInterval(50))
        XCTAssertEqual(store.baseline, now)
        XCTAssertEqual(store.lastRead, ["session": now.addingTimeInterval(10)])
        store.activate(account("two"), now: now.addingTimeInterval(60))
        XCTAssertEqual(store.lastRead, ["other": now.addingTimeInterval(30)])
        store.activate(nil)
        XCTAssertTrue(store.unreadSessionIDs(in: snapshot([message(at: 100)])).isEmpty)
    }

    func testReadTimestampIncludesAlreadyLoadedFutureAgentMessages() {
        let (defaults, name) = preferences()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SessionReadStore(defaults: defaults)
        store.activate(account("one"), now: now)
        store.markRead("session", messages: [message(at: 100), message(at: 200, direction: "boss_to_agent")],
            now: now)
        XCTAssertEqual(store.lastRead["session"], now.addingTimeInterval(100))
        XCTAssertTrue(store.unreadSessionIDs(in: snapshot([message(at: 100)])).isEmpty)
    }

    func testPruningKeepsFiveHundredNewestSessionsAndRemovesOldEntriesOnReload() {
        let (defaults, name) = preferences()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SessionReadStore(defaults: defaults)
        store.activate(account("one"), now: now)
        for index in 0..<501 {
            store.markRead("session-\(index)", messages: [], now: now.addingTimeInterval(Double(index)))
        }
        XCTAssertEqual(store.lastRead.count, 500)
        XCTAssertNil(store.lastRead["session-0"])
        XCTAssertNotNil(store.lastRead["session-500"])
        let restored = SessionReadStore(defaults: defaults)
        restored.activate(account("one"), now: now.addingTimeInterval(31 * 24 * 60 * 60))
        XCTAssertTrue(restored.lastRead.isEmpty)
        XCTAssertEqual(restored.baseline, now)
    }

    private func preferences() -> (UserDefaults, String) {
        let name = "SessionReadStoreTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    private func account(_ identity: String, server: String = "https://unread.invalid") -> SessionReadAccount {
        SessionReadAccount(serverURL: URL(string: server)!, identity: identity)
    }

    private func snapshot(_ messages: [HistoryMessage]) -> OverviewSnapshot {
        OverviewSnapshot(history: messages, live: nil, now: now.addingTimeInterval(200))
    }

    private func message(at seconds: TimeInterval, session: String = "session",
                         direction: String = "agent_to_boss") -> HistoryMessage {
        HistoryMessage(id: MessageID(rawValue: "\(session)-\(seconds)"), body: "Update", agentName: "Agent",
            direction: direction, status: "delivered", priority: "normal",
            createdAt: AttentionTestSupport.iso(now.addingTimeInterval(seconds)), sessionId: session)
    }
}

final class SidebarWorkingCaptionTests: XCTestCase {
    func testSelectedRowDropsGreenSoTheCaptionStaysReadable() {
        XCTAssertTrue(SidebarWorkingCaption.usesStatusColor(.standard))
        XCTAssertFalse(SidebarWorkingCaption.usesStatusColor(.increased),
            "Green on the blue emphasized selection is unreadable")
    }
}
