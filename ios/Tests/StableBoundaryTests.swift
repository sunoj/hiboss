// Regression coverage for authorization invalidation and current-state reply admission.
// Exports StableBoundaryTests with a held verification service.
// Dependencies: XCTest, HibossKit and the native Inbox/Preferences stores.

import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class StableBoundaryTests: XCTestCase {
    override func tearDown() async throws {
        AccountAuthorization.shared.connect(nil)
        try await super.tearDown()
    }

    func testTargetedReadRejectionClearsInboxAndPreferenceDraft() async {
        for status in [401, 403] {
            let api = BoundaryAPI()
            let store = loadedStore(api)
            let preferences = PreferencesStore()
            await preferences.load(api: api)
            preferences.setPrivatePush(true)
            store.messageDrafts["decision"] = "Account draft"
            store.sessionReplyDraft.update("Session draft", targets: [])
            api.failure = status
            _ = await store.loadMessage("decision")
            XCTAssertTrue(store.history.isEmpty)
            XCTAssertTrue(store.openedMessages.isEmpty)
            XCTAssertFalse(preferences.hasLoaded)
            XCTAssertFalse(preferences.isDirty)
            XCTAssertTrue(store.messageDrafts.isEmpty)
            XCTAssertTrue(store.sessionReplyDraft.text.isEmpty)
            store.stop()
        }
    }

    func testHistoryRejectionClearsCachedDecision() async {
        let api = BoundaryAPI()
        let store = loadedStore(api)
        api.failure = 401
        await store.refresh()
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertFalse(store.didLoad)
        store.stop()
    }

    func testOrdinaryTranscriptMessageOutsideCachedHistoryRemainsSendable() async {
        let api = BoundaryAPI()
        let store = loadedStore(api)
        XCTAssertNil(store.message(for: "new-ordinary-message"))
        let result = await store.reply("Noted", to: "new-ordinary-message", isDecision: false)
        XCTAssertEqual(result, .sent)
        XCTAssertEqual(api.posts, 1)
        XCTAssertTrue(store.requiredInputs.contains { $0.id == "decision" },
                      "Sending to an ordinary message must not settle the existing decision")
        store.stop()
    }

    func testUnclassifiedMessageOutsideCachedHistoryCannotPost() async {
        let api = BoundaryAPI()
        let store = loadedStore(api)
        let result = await store.reply("Unknown answer", to: "unknown-message")
        XCTAssertEqual(result, .alreadyResolved)
        XCTAssertEqual(api.posts, 0)
        store.stop()
    }

    func testResolutionWhileVerificationIsHeldNeverPosts() async throws {
        let api = BoundaryAPI()
        let store = loadedStore(api)
        store.requiredInputReady = false
        api.holdVerification = true
        let reply = Pending { await store.reply("Yes", to: "decision") }
        await waitUntil { api.verification != nil }
        store.settleReply(nil, for: "decision", closed: true)
        api.verification?.resume(returning: [BoundaryAPI.decision])
        let result = try await reply.settled()
        XCTAssertEqual(result, .alreadyResolved)
        XCTAssertEqual(api.posts, 0)
        store.stop()
    }

    func testWithdrawalExpiryAndLostCoverageDuringVerificationNeverPost() async throws {
        for change in ["withdrawal", "expiry", "coverage"] {
            let api = BoundaryAPI()
            let store = loadedStore(api)
            store.requiredInputReady = false
            api.holdVerification = true
            let reply = Pending { await store.reply("Yes", to: "decision") }
            await waitUntil { api.verification != nil }
            switch change {
            case "withdrawal": store.withdrawn.insert("decision")
            case "expiry":
                store.requiredInputs = [HistoryMessage(
                    id: "decision", body: "Proceed?", direction: "agent_to_boss", status: "sent",
                    priority: "high", mode: "blocking", metadata: MessageMetadata(options: ["Yes", "No"]),
                    expiresAt: "2000-01-01T00:00:00Z", createdAt: ""
                )]
            default: store.requiredInputLoaded = false
            }
            api.verification?.resume(returning: [BoundaryAPI.decision])
            let result = try await reply.settled()
            XCTAssertEqual(result, change == "coverage" ? .failed : .alreadyResolved)
            XCTAssertEqual(api.posts, 0)
            store.stop()
        }
    }

    func testPreferencesLoadAndSaveRejectionsClearTheAccount() async {
        for status in [401, 403] {
            for saving in [false, true] {
                let api = BoundaryAPI()
                let inbox = loadedStore(api)
                let preferences = PreferencesStore()
                await preferences.load(api: api)
                if saving { preferences.setPrivatePush(true) }
                api.failure = status
                if saving { await preferences.save() }
                else { await preferences.load(api: api) }
                XCTAssertFalse(preferences.hasLoaded)
                XCTAssertFalse(preferences.isDirty)
                XCTAssertTrue(inbox.history.isEmpty)
                let posts = api.posts
                await preferences.save()
                XCTAssertEqual(api.posts, posts)
                inbox.stop()
            }
        }
    }

    func testIntentGateVerificationAndWriteRejectionsClearTheAccount() async {
        for status in [401, 403] {
            for verifying in [true, false] {
                let api = BoundaryAPI()
                let inbox = loadedStore(api)
                let preferences = PreferencesStore()
                await preferences.load(api: api)
                preferences.setPrivatePush(true)
                api.failure = status
                api.rejectVerification = verifying
                _ = await inbox.replyGate.submit("Yes", to: "decision", via: api,
                    onAuthorizationFailure: { AccountAuthorization.shared.reject($0) })
                XCTAssertTrue(inbox.history.isEmpty)
                XCTAssertFalse(preferences.hasLoaded)
                XCTAssertFalse(preferences.isDirty)
                XCTAssertEqual(api.posts, verifying ? 0 : 1)
                inbox.stop()
            }
        }
    }

    private func loadedStore(_ api: BoundaryAPI) -> InboxStore {
        let store = InboxStore(decisionAlertsEnabled: false, replyGate: DecisionReplyGate())
        store.api = api
        store.history = [BoundaryAPI.decision]
        store.requiredInputs = [BoundaryAPI.decision]
        store.retainOpenMessage(BoundaryAPI.decision)
        store.requiredInputLoaded = true
        store.requiredInputReady = true
        store.didLoad = true
        return store
    }
}

@MainActor
final class BoundaryAPI: BossServing, RequiredInputServing, BossPreferencesServing {
    var failure: Int?
    var holdVerification = false
    var rejectVerification = false
    var verification: CheckedContinuation<[HistoryMessage], Never>?
    var posts = 0
    static let decision = HistoryMessage(
        id: "decision", body: "Proceed?", direction: "agent_to_boss", status: "sent", priority: "high",
        mode: "blocking", metadata: MessageMetadata(options: ["Yes", "No"]), createdAt: ""
    )

    func check() throws {
        if let failure { throw HibossAPIError.requestFailed(status: failure, message: "Rejected") }
    }
    func fetchMessage(_ id: MessageID) async throws -> MessageDetail {
        try check()
        return MessageDetail(message: Self.decision, replies: [])
    }
    func fetchHistory() async throws -> [HistoryMessage] { try check(); return [] }
    func fetchRequiredInputs() async throws -> [HistoryMessage] {
        // History is the rejecting source in its regression, independently of coverage reads.
        if rejectVerification { try check() }
        if holdVerification { return await withCheckedContinuation { verification = $0 } }
        return [Self.decision]
    }
    func reply(to id: MessageID, with choice: String) async throws -> ReplyOutcome {
        posts += 1
        try check()
        return .accepted
    }
    func fetchPreferences() async throws -> BossPreferences { try check(); return BossPreferences() }
    func updatePreferences(_ preferences: BossPreferences) async throws -> BossPreferences {
        try check()
        return preferences
    }
    func messageStream() async -> AsyncThrowingStream<BossEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func feedStream() async -> AsyncThrowingStream<HistoryMessage, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func requiredInputStream() async -> AsyncThrowingStream<RequiredInputEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
