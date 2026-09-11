// Unit coverage for notification filtering, deduplication, formatting, and authorization.
// Exports: MessageNotificationTests using a fake center without OS notification access.
// Dependencies: XCTest, HibossKit, and the macOS notification store.

import XCTest
import HibossKit
@testable import HibossIsland

@MainActor
final class MessageNotificationTests: XCTestCase {
    private var defaults: UserDefaults = .standard
    private var suiteName = ""

    override func setUp() async throws {
        suiteName = "MessageNotificationTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testOptionsIncludingExpiredOptionsAreSkipped() async {
        let center = RecordingNotificationCenter()
        let store = MessageNotificationStore(center: center, defaults: defaults)
        await store.receive(message(metadata: MessageMetadata(options: ["Yes"])))
        await store.receive(message(id: "expired", metadata: MessageMetadata(options: ["Yes"], isExpired: true)))
        XCTAssertTrue(center.notices.isEmpty)
    }

    func testDuplicatesAreSkippedAcrossDisconnects() async {
        let center = RecordingNotificationCenter()
        let store = MessageNotificationStore(center: center, defaults: defaults)
        await store.receive(message())
        store.disconnect()
        await store.receive(message())
        XCTAssertEqual(center.notices.count, 1)
    }

    func testOnlyAgentToBossDirectionPosts() async {
        let center = RecordingNotificationCenter()
        let store = MessageNotificationStore(center: center, defaults: defaults)
        await store.receive(message(id: "outbound", direction: "boss_to_agent"))
        await store.receive(message(id: "peer", direction: "agent_to_agent"))
        await store.receive(message())
        XCTAssertEqual(center.notices.map(\.messageID), ["plain"])
    }

    func testTitleBodyAndThreadFormatting() {
        let notice = MessageNotice(message: message(body: "  first\n second\tthird  "))
        XCTAssertEqual(notice.title, "Builder · Release")
        XCTAssertEqual(notice.body, "first second third")
        XCTAssertEqual(notice.threadIdentifier, "session-1")
        XCTAssertEqual(notice.messageID, "plain")
    }

    func testBodyTruncationPreservesUnicodeCharacters() {
        let notice = MessageNotice(message: message(body: String(repeating: "👨‍👩‍👧‍👦", count: 300)))
        XCTAssertEqual(notice.body.count, MessageNotice.bodyLimit)
        XCTAssertEqual(notice.body.last, "…")
        XCTAssertEqual(notice.body.first, "👨‍👩‍👧‍👦")
    }

    func testMissingSessionUsesAgentOnlyAndNoThread() {
        let notice = MessageNotice(message: message(sessionID: nil, sessionLabel: "  "))
        XCTAssertEqual(notice.title, "Builder")
        XCTAssertEqual(notice.threadIdentifier, "")
    }

    func testToggleOffSuppressesPostingAndDoesNotReplayOnEnable() async {
        let center = RecordingNotificationCenter()
        let store = MessageNotificationStore(center: center, defaults: defaults)
        XCTAssertTrue(store.isEnabled)
        store.setEnabled(false)
        await store.receive(message())
        store.setEnabled(true)
        await store.receive(message())
        XCTAssertTrue(center.notices.isEmpty)
        await store.receive(message(id: "new"))
        XCTAssertEqual(center.notices.count, 1)
    }

    func testDisabledPreferencePersistsWithoutRequestingAuthorization() async {
        let center = RecordingNotificationCenter()
        center.status = .notDetermined
        let store = MessageNotificationStore(center: center, defaults: defaults)
        store.setEnabled(false)
        let restored = MessageNotificationStore(center: center, defaults: defaults)
        await restored.prepareAuthorization()
        XCTAssertFalse(restored.isEnabled)
        XCTAssertEqual(center.requestCount, 0)
    }

    func testFirstEnableRequestsAuthorizationOnlyOnce() async {
        let center = RecordingNotificationCenter()
        center.status = .notDetermined
        let store = MessageNotificationStore(center: center, defaults: defaults)
        await store.prepareAuthorization()
        await store.prepareAuthorization()
        XCTAssertEqual(center.requestCount, 1)
        XCTAssertEqual(store.authorization, .authorized)
    }

    func testDeniedAuthorizationSuppressesPostingAndDoesNotPromptAgain() async {
        let center = RecordingNotificationCenter()
        center.status = .denied
        let store = MessageNotificationStore(center: center, defaults: defaults)
        await store.receive(message())
        XCTAssertEqual(store.authorization, .denied)
        XCTAssertEqual(center.requestCount, 0)
        XCTAssertTrue(center.notices.isEmpty)
    }

    func testFeedReconnectsAfterFailureAndEOFWithoutDuplicating() async throws {
        let center = RecordingNotificationCenter()
        let api = ReconnectingFeedAPI(message: message())
        let store = MessageNotificationStore(center: center, defaults: defaults,
            reconnectDelay: .milliseconds(20))
        store.connect(api: api)
        defer { store.disconnect() }
        for _ in 0..<100 {
            if await api.attempts >= 3 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let attempts = await api.attempts
        XCTAssertGreaterThanOrEqual(attempts, 3)
        XCTAssertEqual(center.notices.count, 1)
        store.disconnect()
        try await Task.sleep(for: .milliseconds(60))
        let stoppedAttempts = await api.attempts
        XCTAssertEqual(stoppedAttempts, attempts)
        XCTAssertEqual(store.connectionState, .disconnected)
    }

    private func message(
        id: MessageID = "plain", body: String = "ping", direction: String = "agent_to_boss",
        metadata: MessageMetadata? = nil, sessionID: String? = "session-1", sessionLabel: String? = " Release "
    ) -> HistoryMessage {
        HistoryMessage(id: id, body: body, agentName: " Builder ", direction: direction,
            status: "pending", priority: "normal", metadata: metadata, createdAt: "2026-09-11 12:00:00",
            sessionId: sessionID, sessionLabel: sessionLabel)
    }
}

@MainActor
private final class RecordingNotificationCenter: MessageNotificationCenter {
    var isEnabled = true
    var status: MessageNotificationAuthorization = .authorized
    var notices: [MessageNotice] = []
    var requestCount = 0

    func authorization() async -> MessageNotificationAuthorization { status }
    func requestAuthorization() async throws { requestCount += 1; status = .authorized }
    func post(_ notice: MessageNotice) async throws { notices.append(notice) }
}

private actor ReconnectingFeedAPI: BossServing {
    let message: HistoryMessage
    private(set) var attempts = 0

    init(message: HistoryMessage) { self.message = message }

    func feedStream() async -> AsyncThrowingStream<HistoryMessage, Error> {
        attempts += 1
        let shouldFail = attempts == 1
        return AsyncThrowingStream { continuation in
            if shouldFail {
                continuation.finish(throwing: TestError.rejected)
            } else {
                continuation.yield(message)
                continuation.finish()
            }
        }
    }

    func messageStream() async -> AsyncThrowingStream<BossEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func fetchHistory() async throws -> [HistoryMessage] { [] }
    func fetchMessage(_ messageID: MessageID) async throws -> MessageDetail { throw TestError.rejected }
    func reply(to messageID: MessageID, with choice: String) async throws -> ReplyOutcome { .accepted }
}
