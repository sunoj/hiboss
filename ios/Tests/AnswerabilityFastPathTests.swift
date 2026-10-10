// The per-row answerability check must equal membership in the Today snapshot's decisions,
// without building the snapshot (it ran per row per redraw and froze large real inboxes).

import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class AnswerabilityFastPathTests: XCTestCase {
    private func ask(_ id: MessageID, expiresIn: TimeInterval? = nil, options: [String] = ["Yes", "No"],
                     mode: String = "async") -> HistoryMessage {
        HistoryMessage(id: id, body: "Q \(id)", agentName: "agent", direction: "agent_to_boss",
            status: "delivered", priority: "normal", channel: "api", mode: mode,
            metadata: MessageMetadata(options: options),
            expiresAt: expiresIn.map { Date.now.addingTimeInterval($0).ISO8601Format() },
            createdAt: Date.now.addingTimeInterval(-60).ISO8601Format(), sessionId: "s", sessionLabel: "p")
    }

    func testFastPathMatchesTheSnapshotForEveryCase() {
        let open = ask("open")
        let expired = ask("expired", expiresIn: -30)
        let withdrawn = ask("withdrawn")
        let historyOnly = ask("history-only")
        let note = ask("note", options: [])
        let store = InboxStore(decisionAlertsEnabled: false)
        store.history = [open, expired, withdrawn, historyOnly, note]
        store.requiredInputs = [open, expired, withdrawn, note]
        store.withdrawn = ["withdrawn"]
        store.requiredInputLoaded = true
        let decisions = Set(store.todaySnapshot(now: .now).decisions.map(\.id))
        for id: MessageID in ["open", "expired", "withdrawn", "history-only", "note"] {
            let fast = store.answerability(for: id) == .open
            XCTAssertEqual(fast, decisions.contains(id), "answerability for \(id)")
        }
        XCTAssertEqual(store.answerability(for: "open"), .open)
    }

    func testUnknownBeforeTheListLoads() {
        let store = InboxStore(decisionAlertsEnabled: false)
        store.requiredInputs = [ask("open")]
        XCTAssertEqual(store.answerability(for: "open"), .checking)
    }
}
