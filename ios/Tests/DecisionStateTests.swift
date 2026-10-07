// Decision-state tests: a timeout default is attributed by its `auto_default` marker, never by
// its source, through history reloads and Live Activity completion; a failed refresh over
// loaded rows is reported as stale.
// Exports: DecisionStateTests. Dependencies: XCTest, HiBoss app target, HibossKit, HeldReplyAPI.

import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class DecisionStateTests: XCTestCase {
    private func metadata(_ json: String) throws -> MessageMetadata {
        try JSONDecoder().decode(MessageMetadata.self, from: Data(json.utf8))
    }

    private func reply(_ body: String, _ metadata: MessageMetadata) -> HistoryMessage {
        HistoryMessage(
            id: "r-q1", body: body, agentName: "agent", direction: "boss_to_agent", status: "sent",
            priority: "normal", replyTo: "q1", metadata: metadata, createdAt: "2026-10-04T10:01:00Z"
        )
    }

    private static let question = HistoryMessage(
        id: "q1", body: "Rotate the key?", agentName: "agent", direction: "agent_to_boss",
        status: "replied", priority: "normal", mode: "blocking",
        metadata: MessageMetadata(options: ["Rotate", "Keep"], defaultOption: "Keep"),
        createdAt: "2026-10-04T10:00:00Z"
    )

    func testMarkerNotSourceMakesAReplyAutomatic() throws {
        for json in [#"{"auto_default":true,"source":"api"}"#, #"{"auto_default":true,"source":"system"}"#] {
            let settled = try XCTUnwrap(DecisionSettlement(reply: reply("Keep", try metadata(json))))
            XCTAssertTrue(settled.isAutoDefault, json)
            XCTAssertFalse(settled.answeredElsewhere, "a timeout default is not an answer from \(json)")
            XCTAssertEqual(settled.symbol, "clock.arrow.circlepath")
        }
        let api = try XCTUnwrap(DecisionSettlement(reply: reply("Keep", try metadata(#"{"source":"api"}"#))))
        XCTAssertFalse(api.isAutoDefault)
        XCTAssertTrue(api.answeredElsewhere)
        XCTAssertEqual(api.symbol, "checkmark.circle.fill")
    }

    func testBossChoosingTheDefaultIsNotAutomatic() throws {
        let chosen = try XCTUnwrap(
            DecisionSettlement(reply: reply("Keep", try metadata(#"{"source":"ios"}"#))))
        XCTAssertEqual(chosen.answer, Self.question.defaultOption)
        XCTAssertFalse(chosen.isAutoDefault, "equal to the default is still the boss's choice")
        XCTAssertFalse(chosen.answeredElsewhere)
    }

    func testHistoryReloadKeepsAHistoricalTimeoutDefaultAutomatic() async throws {
        let historical = reply("Keep", try metadata(#"{"auto_default":true,"source":"api"}"#))
        let api = HeldReplyAPI(history: [Self.question, historical])
        let store = InboxStore(reconnectDelay: .milliseconds(10), decisionAlertsEnabled: false,
                               replyGate: DecisionReplyGate())
        store.start(api: api)
        await store.refresh()
        let settled = try XCTUnwrap(store.settlement(for: "q1"))
        XCTAssertTrue(settled.isAutoDefault, "history must not turn an automatic answer into one from API")
        XCTAssertFalse(settled.answeredElsewhere)
        XCTAssertEqual(store.settledCards.map(\.id), ["q1"], "the Resolved list reads this settlement")
    }

    func testStreamResolutionThenHistoryStayAutomatic() throws {
        let streamed = try XCTUnwrap(DecisionSettlement(resolution: OptionResolution(
            id: "q1", status: .replied, answer: "Keep", source: "system"
        )))
        XCTAssertTrue(streamed.isAutoDefault)
        XCTAssertNil(DecisionSettlement(resolution: OptionResolution(id: "q1", status: .expired)))
    }

    /// The Live Activity ends with the recorded reply's attribution: the marker, never the
    /// source or equality with the default, makes it "Auto-selected when time ran out".
    func testLiveActivityCompletionIsAttributedByTheRecordedMarker() async throws {
        func completion(_ submission: DecisionSubmission, recorded json: String?) async throws
            -> DecisionCompletion?
        {
            let detail = try json.map {
                MessageDetail(message: Self.question, replies: [reply("Keep", try metadata($0))])
            }
            return await DecisionActivityLink.completion(of: "q1", after: submission, choice: "Keep",
                                                         api: HeldReplyAPI(detail: detail))
        }
        let automatic = try await completion(
            .alreadyResolved, recorded: #"{"auto_default":true,"source":"api"}"#)
        XCTAssertEqual(automatic, .autoSelected("Keep"))
        let unmarked = try await completion(.alreadyResolved, recorded: #"{"source":"system"}"#)
        XCTAssertEqual(unmarked, .answeredElsewhere("Keep"), "a source alone is not the marker")
        let unreadable = try await completion(.alreadyResolved, recorded: nil)
        XCTAssertEqual(unreadable, .answeredElsewhere(nil))
        let mine = try await completion(.accepted, recorded: #"{"auto_default":true}"#)
        XCTAssertEqual(mine, .answered("Keep"), "this device's choice of the default is the boss's answer")
        let failed = try await completion(.failed("down"), recorded: nil)
        XCTAssertNil(failed, "a failed send keeps the activity open")
    }

    func testListPhaseKeepsRowsAndReportsAFailedRefresh() {
        XCTAssertEqual(ListStatePhase.resolve(isLoading: true, error: nil, isEmpty: true), .loading)
        XCTAssertEqual(
            ListStatePhase.resolve(isLoading: false, error: "down", isEmpty: true), .unreachable("down"))
        XCTAssertEqual(ListStatePhase.resolve(isLoading: false, error: nil, isEmpty: true), .empty)
        XCTAssertEqual(ListStatePhase.resolve(isLoading: true, error: nil, isEmpty: true, hasLoaded: true),
                       .empty, "Refreshing a previously empty result must retain the cached state")
        XCTAssertEqual(ListStatePhase.resolve(isLoading: false, error: "down", isEmpty: false),
                       .content(staleError: "down"))
        XCTAssertEqual(ListStatePhase.resolve(isLoading: false, error: nil, isEmpty: false),
                       .content(staleError: nil))
    }
}
