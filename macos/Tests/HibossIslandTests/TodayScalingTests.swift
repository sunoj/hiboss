// Guards linear required-input merging while retaining history order and replacement semantics.
// Exports: TodayScalingTests; CPU comparison uses the same messages and process clock.
// Dependencies: XCTest, HibossKit, TodayProjection and PerfSurveyMetrics.

import XCTest
import HibossKit
@testable import HibossIsland

@MainActor
final class TodayScalingTests: XCTestCase {
    func testRequiredInputMergeHasIndexedCPUCost() {
        let history = (0..<20_000).map { index in
            HistoryMessage(id: MessageID(rawValue: "message-\(index)"), body: "Update",
                direction: "agent_to_boss", status: "delivered", priority: "normal", createdAt: "")
        }
        let start = PerfSurveyMetrics.processCPU()
        var indices: [MessageID: Int] = [:]
        for (index, message) in history.enumerated() { indices[message.id] = index }
        var expected = history
        for message in history { expected[indices[message.id]!] = message }
        let indexedCPU = PerfSurveyMetrics.processCPU() - start
        let mergeStart = PerfSurveyMetrics.processCPU()
        let actual = TodayProjection.merge(history: history, live: nil, requiredInputs: history)
        let mergeCPU = PerfSurveyMetrics.processCPU() - mergeStart
        XCTAssertEqual(actual, expected)
        print("Required-input merge CPU: \(mergeCPU); indexed reference: \(indexedCPU)")
        XCTAssertLessThan(mergeCPU, max(0.03, indexedCPU * 5))
    }

    func testMergeReplacesFirstHistoryDuplicateAndAppendsNewIDsInOrder() {
        let first = AttentionTestSupport.ask(id: "a", options: ["First"])
        let second = AttentionTestSupport.ask(id: "a", options: ["Second"])
        let new = AttentionTestSupport.ask(id: "b", options: ["New"])
        XCTAssertEqual(TodayProjection.merge(history: [first, first], live: nil,
            requiredInputs: [new, first, second]), [second, first, new])
    }

    func testDestinationLookupsReuseProjectedStorage() {
        let messages = [AttentionTestSupport.ask(id: "a", options: ["Ship"]),
            AttentionTestSupport.ask(id: "b", options: ["Wait"])]
        let snapshot = OverviewSnapshot(history: messages, live: nil, now: AttentionTestSupport.now,
            requiredInputs: messages, requiredInputLoaded: true)
        for destination in [OverviewDestination.category(.needsYou), .session("a")] {
            let first = snapshot.messages(for: destination)
            let second = snapshot.messages(for: destination)
            XCTAssertFalse(first.isEmpty)
            first.withUnsafeBufferPointer { left in
                second.withUnsafeBufferPointer { right in
                    XCTAssertEqual(left.baseAddress, right.baseAddress,
                        "Destination reads must reuse the snapshot projection")
                }
            }
        }
        for category in OverviewCategory.allCases where category.isAttention {
            XCTAssertEqual(snapshot.attention(for: category).map(\.message),
                snapshot.messages(for: .category(category)))
        }
    }
}
