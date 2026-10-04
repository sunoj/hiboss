// The notification action handler and RespondDecisionIntent.perform(), run unmodified against
// a held fake server, are admitted by the same per-decision gate as the in-app reply path.
// Exports: DecisionEntryPointTests. Dependencies: XCTest, HiBoss app target, HeldReplyAPI, Pending.

import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class DecisionEntryPointTests: XCTestCase {
    private let server = HeldReplyAPI()

    override func setUp() async throws {
        let server = server
        HiBossStore.replyAPI = { server }
    }

    override func tearDown() async throws {
        HiBossStore.replyAPI = { HiBossStore.bossAPI() }
    }

    func testNotificationActionIsAdmittedByTheSharedGate() async throws {
        func action(_ identifier: String) -> PushActionRequest {
            PushActionRequest(messageID: "push-q1", cachedMessage: nil, options: ["Approve", "Reject"],
                              actionIdentifier: identifier, replyText: nil)
        }
        try await assertAdmitted(id: "push-q1", choice: "Reject",
                                 first: { await PushManager.shared.handle(action(PushAction.reject)) },
                                 again: { await PushManager.shared.handle(action(PushAction.approve)) })
    }

    func testLiveActivityIntentIsAdmittedByTheSharedGate() async throws {
        func perform(_ choice: String) async {
            _ = try? await RespondDecisionIntent(messageID: "intent-q1", choice: choice).perform()
        }
        try await assertAdmitted(id: "intent-q1", choice: "Reject",
                                 first: { await perform("Reject") }, again: { await perform("Approve") })
    }

    /// `first` sends `choice` and is held at the server. While it is in flight the in-app
    /// buttons read it, an in-app reply is refused, and a repeat of the entry point sends
    /// nothing. Release lands exactly one reply and frees the decision.
    private func assertAdmitted(
        id: MessageID, choice: String,
        first: @escaping @MainActor () async -> Void, again: @escaping @MainActor () async -> Void
    ) async throws {
        let appAPI = HeldReplyAPI()
        let store = InboxStore(reconnectDelay: .milliseconds(10), decisionAlertsEnabled: false)
        store.start(api: appAPI)
        let external = Pending { await first() }
        await waitUntil { server.replies.count == 1 }
        XCTAssertEqual(server.replies, [choice], "the entry point reached the server")
        XCTAssertEqual(store.replying[id], choice, "the in-app buttons are disabled by the external reply")

        let inApp = Pending { await store.reply("Approve", to: id) }
        let repeated = Pending { await again() }
        await waitUntil { (inApp.isDone && repeated.isDone) || !appAPI.replies.isEmpty || server.replies.count > 1 }
        server.release()
        appAPI.release()
        let inAppResult = try await inApp.settled()
        try await repeated.settled()
        try await external.settled()

        XCTAssertEqual(inAppResult, .busy)
        XCTAssertEqual(appAPI.replies, [], "the in-app reply never reached the server")
        XCTAssertEqual(server.replies, [choice], "a repeated action sent nothing")
        XCTAssertNil(store.replying[id], "the landed reply frees the decision")
    }
}
