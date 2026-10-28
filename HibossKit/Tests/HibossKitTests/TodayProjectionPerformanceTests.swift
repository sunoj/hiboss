// Measures the shared Today projection at normal and larger history sizes.
// Exports: TodayProjectionPerformanceTests with fixed timestamps and twenty sessions.
// Dependencies: XCTest, TodaySnapshot, and TodayTestSupport.

import XCTest
import HibossKit

final class TodayProjectionPerformanceTests: XCTestCase {
    func testOneHundredMessages() {
        measureSnapshot(messageCount: 100)
    }

    func testOneThousandMessages() {
        measureSnapshot(messageCount: 1_000)
    }

    private func measureSnapshot(messageCount: Int) {
        let history = (0..<messageCount).reversed().map { index in
            TodayTestSupport.message("message-\(index)", session: "session-\(index % 20)",
                age: TimeInterval(index), sessionStatus: "working")
        }
        let required = (0..<20).map { index in
            TodayTestSupport.message("decision-\(index)", session: "session-\(index)",
                options: ["Ship", "Wait"], expiresIn: 300, defaultOption: "Wait")
        }
        // Warm the shared timestamp cache before measuring repeated native redraws.
        _ = TodayTestSupport.snapshot(history, requiredInputs: required)
        measure {
            for _ in 0..<20 {
                let snapshot = TodayTestSupport.snapshot(history, requiredInputs: required)
                XCTAssertEqual(snapshot.decisions.count, 20)
                XCTAssertEqual(snapshot.sessionDirectory.needsYou.count, 20)
                XCTAssertEqual(snapshot.delivered.count, 20)
            }
        }
    }
}
