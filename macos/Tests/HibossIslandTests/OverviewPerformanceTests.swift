// Benchmarks overview derivation at the API's 100-message page size.
// Exports: OverviewPerformanceTests with repeatable SQL timestamps and 20 sessions.
// Dependencies: XCTest, HibossKit, OverviewSnapshot.

import XCTest
import HibossKit
@testable import HibossIsland

final class OverviewPerformanceTests: XCTestCase {
    func testSnapshotForOneHundredMessages() {
        let history = (0..<100).map { index in
            HistoryMessage(id: MessageID(rawValue: "message-\(index)"), body: "Deployment update",
                agentName: "Agent", direction: "agent_to_boss", status: "delivered",
                priority: "normal", createdAt: "2026-09-05 10:00:00",
                sessionId: "session-\(index % 20)", sessionLabel: "project-\(index % 20)/main")
        }
        measure {
            let snapshot = OverviewSnapshot(history: history, live: nil, now: AttentionTestSupport.now)
            XCTAssertEqual(snapshot.count(.all), 100)
            XCTAssertEqual(snapshot.sessions.count, 20)
        }
    }
}
