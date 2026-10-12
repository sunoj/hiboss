// Verifies account rejection clears macOS content, authority and editable reply/preferences state.
// Exports AccountAuthorizationTests with a local history and preferences service.
// Dependencies: XCTest, Combine, HibossKit and native stores; no windows or network.

import Combine
import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class AccountAuthorizationTests: XCTestCase {
    func testRejectionClearsHistoryPreferenceAndReplyDrafts() async {
        defer { AccountAuthorization.shared.connect(nil) }
        for status in [401, 403] {
            AccountAuthorization.shared.connect(nil)
            let api = AccountContentAPI()
            let flow = OptionFlowStore()
            flow.connect(api: api)
            await flow.refreshHistory()
            XCTAssertEqual(flow.historyMessages.count, 1)
            let preferences = BossPreferencesStore(api: api)
            await preferences.load()
            XCTAssertEqual(preferences.preferences.privatePush, true)
            let reply = AttentionReplyState()
            reply.drafts["cached"] = "Private draft"
            AccountAuthorization.shared.reject(HibossAPIError.requestFailed(status: status, message: ""))
            XCTAssertTrue(flow.historyMessages.isEmpty)
            XCTAssertNil(flow.activeMessage)
            XCTAssertNil(flow.historyLoadedAt)
            XCTAssertEqual(preferences.preferences, BossPreferences())
            XCTAssertTrue(reply.drafts.isEmpty)
            await preferences.save()
            let saves = await api.saves
            XCTAssertEqual(saves, 0, "Rejected account must not retain a writable preference editor")
            AccountAuthorization.shared.connect(nil)
            await preferences.load()
            XCTAssertEqual(preferences.preferences.privatePush, true, "Explicit reconnection can load again")
            flow.disconnect()
        }
    }

    func testDeviceRequestsResumeAfterSuccessfulAccountConnection() async throws {
        let api = ReconnectingJoinAPI()
        let requests = JoinRequestsModel { api }
        await requests.refresh()
        XCTAssertEqual(api.reads, 1)
        AccountAuthorization.shared.reject(HibossAPIError.requestFailed(status: 401, message: ""))
        await requests.refresh()
        XCTAssertEqual(api.reads, 1)
        let account = ConnectionConfig(serverURL: try XCTUnwrap(URL(string: "https://unit.test")),
                                       bossToken: "unit-token")
        AccountAuthorization.shared.connect(account)
        defer { AccountAuthorization.shared.connect(nil) }
        await requests.refresh()
        XCTAssertEqual(api.reads, 2)
        XCTAssertFalse(requests.isForbidden)
        XCTAssertTrue(requests.didLoad)
    }

    func testRejectionDisconnectsRequiredInputAuthority() async {
        let api = ControlledRequiredInputs(messages: [])
        let store = RequiredInputStore()
        store.connect(api)
        AccountAuthorization.shared.reject(HibossAPIError.requestFailed(status: 403, message: ""))
        XCTAssertEqual(store.state, RequiredInputState())
        store.refresh()
        XCTAssertFalse(store.state.refreshing)
        store.disconnect()
        AccountAuthorization.shared.connect(nil)
    }

    func testRejectedPreferenceResponseCannotRestoreReplyDraftAfterAwait() async {
        let state = AttentionReplyState()
        state.drafts["cached"] = "Private draft"
        await state.send("Private draft", for: "cached") { _, _ in
            AccountAuthorization.shared.reject(HibossAPIError.requestFailed(status: 401, message: ""))
            return .failed("Rejected")
        }
        XCTAssertTrue(state.drafts.isEmpty)
        XCTAssertTrue(state.errors.isEmpty)
        XCTAssertTrue(state.submitting.isEmpty)
        AccountAuthorization.shared.connect(nil)
    }
}

private actor AccountContentAPI: BossServing, BossPreferencesServing {
    private(set) var saves = 0
    func fetchHistory() async throws -> [HistoryMessage] {
        [HistoryMessage(id: "cached", body: "Cached", direction: "agent_to_boss", status: "delivered",
                        priority: "normal", createdAt: "2026-10-01T00:00:00Z")]
    }
    func fetchMessage(_ id: MessageID) async throws -> MessageDetail { throw URLError(.badURL) }
    func reply(to id: MessageID, with choice: String) async throws -> ReplyOutcome { .accepted }
    func messageStream() async -> AsyncThrowingStream<BossEvent, Error> { AsyncThrowingStream { _ in } }
    func feedStream() async -> AsyncThrowingStream<HistoryMessage, Error> { AsyncThrowingStream { _ in } }
    func fetchPreferences() async throws -> BossPreferences { BossPreferences(privatePush: true) }
    func updatePreferences(_ preferences: BossPreferences) async throws -> BossPreferences {
        saves += 1
        return preferences
    }
}

@MainActor
private final class ReconnectingJoinAPI: JoinRequestServing {
    private(set) var reads = 0
    func listPendingJoinRequests() async throws -> [JoinRequest] {
        reads += 1
        return []
    }
    func approveJoinRequest(id: String) async throws -> JoinApproval { throw JoinRequestError.notFound }
    func rejectJoinRequest(id: String) async throws {}
}
