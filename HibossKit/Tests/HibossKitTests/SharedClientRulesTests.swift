// Pins the business rules both native clients share: unread, answer sources, attribution.
// Exports: SharedClientRulesTests.
// Dependencies: XCTest and HibossKit's SessionUnread, AnswerSource, and AnswerAttribution.

import XCTest
@testable import HibossKit

final class SharedClientRulesTests: XCTestCase {
    private let baseline = Date(timeIntervalSince1970: 1_800_000_000)

    func testOnlyAgentToBossMessagesMakeASessionUnread() {
        for (direction, unread) in [("agent_to_boss", true), (" AGENT_TO_BOSS \n", true),
                                    ("agent_to_agent", false), ("boss_to_agent", false), ("unknown", false)] {
            let message = HistoryMessage(id: "m", body: "b", direction: direction, status: "delivered",
                priority: "normal", createdAt: baseline.addingTimeInterval(10).ISO8601Format(),
                sessionId: "s")
            XCTAssertEqual(SessionUnread.isUnread(sessionID: "s", messages: [message], lastRead: nil,
                baseline: baseline), unread, direction)
        }
    }

    func testAnswerSourcesUseOneBrandCasing() {
        let expected = ["ios": "iOS", "ipados": "iPadOS", "macos": "macOS", "mac": "macOS",
            "watchos": "watchOS", "cli": "CLI", "web": "Web", "api": "API", "telegram": "Telegram",
            "discord": "Discord", "custom client": "Custom Client"]
        for (raw, label) in expected {
            XCTAssertEqual(AnswerSource.label(raw), label)
            XCTAssertEqual(AnswerSource.label(raw.uppercased()), label)
        }
        XCTAssertNil(AnswerSource.visibleLabel("macOS", hiding: "macos"))
        XCTAssertNil(AnswerSource.visibleLabel(" ", hiding: "macos"))
        XCTAssertNil(AnswerSource.visibleLabel(nil, hiding: "ios"))
        XCTAssertEqual(AnswerSource.visibleLabel("api", hiding: "ios"), "API")
    }

    func testAttributionNeverWordsATimeoutDefaultAsAnAnswer() {
        XCTAssertEqual(AnswerAttribution.text(isAutoDefault: true, sourceLabel: "API"),
                       AnswerAttribution.autoSelected)
        XCTAssertEqual(AnswerAttribution.text(isAutoDefault: false, sourceLabel: "Telegram"),
                       AnswerAttribution.answeredOn("Telegram"))
        XCTAssertEqual(AnswerAttribution.text(isAutoDefault: false, sourceLabel: nil),
                       AnswerAttribution.answered)
    }

    func testAnswerabilityWithdrawnWinsThenLoadingThenListedIDs() {
        XCTAssertEqual(DecisionAnswerability(id: "a", openIDs: ["a"], loaded: true, withdrawn: ["a"]), .closed)
        XCTAssertEqual(DecisionAnswerability(id: "a", openIDs: ["a"], loaded: false), .checking)
        XCTAssertEqual(DecisionAnswerability(id: "a", openIDs: ["a"], loaded: true), .open)
        XCTAssertEqual(DecisionAnswerability(id: "b", openIDs: ["a"], loaded: true), .closed)
    }

    func testTopDecisionIsTheFirstRankedIncludingTextAsks() {
        let now = baseline
        let option = HistoryMessage(id: "option", body: "Ship?", direction: "agent_to_boss", status: "delivered",
            priority: "low", mode: "blocking", metadata: MessageMetadata(options: ["Yes", "No"]),
            createdAt: now.ISO8601Format())
        let text = HistoryMessage(id: "text", body: "Which host?", direction: "agent_to_boss",
            status: "delivered", priority: "critical", mode: "blocking", createdAt: now.ISO8601Format())
        let snapshot = TodaySnapshot(history: [], requiredInputs: [option, text],
            health: .live(checkedAt: now), coverageComplete: true, now: now)
        XCTAssertEqual(snapshot.decisions.map(\.id), ["text", "option"])
        XCTAssertEqual(snapshot.topDecision()?.id, "text")
        XCTAssertEqual(snapshot.topDecision(skipping: ["text"])?.id, "option")
        XCTAssertNil(snapshot.topDecision(skipping: ["text", "option"]))
    }
}
