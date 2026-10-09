// Verifies iOS Today and Live Activity consume the same shared snapshot.
// Exports TodayProjectionTests for merged coverage, withdrawal, and session buckets.
// Dependencies: XCTest, HiBoss InboxStore, and HibossKit TodaySnapshot.

import HibossKit
import SwiftUI
import XCTest
import UIKit
@testable import HiBoss

@MainActor
final class TodayProjectionTests: XCTestCase {
    func testHistoryAndRequiredInputsShareRankingWithLiveActivity() {
        let store = InboxStore(decisionAlertsEnabled: false)
        let now = Date()
        store.history = [decision("priority", now: now), decision("withdrawn", now: now)]
        store.requiredInputs = [decision("auto", now: now, deadline: now.addingTimeInterval(60))]
        store.withdrawn = ["withdrawn"]
        let today = store.todaySnapshot(now: now)
        XCTAssertEqual(today.decisions.map(\.id), ["auto", "priority"])
        XCTAssertEqual(DecisionActivityManager.rankedMessages(from: today.decisions.map(\.message), now: now)
            .map(\.id), today.decisions.map(\.id))
        XCTAssertEqual(today.sessionDirectory.needsYou.map(\.id), ["session-auto", "session-priority"])
        XCTAssertFalse(today.isAllClear, "offline incomplete coverage cannot claim all-clear")
    }

    func testActivitySinkReceivesTheSameRankedDecisionsAsToday() async {
        var received: [HistoryMessage] = []
        let store = InboxStore(decisionActivitySync: { candidates, _ in received = candidates })
        let now = Date()
        store.requiredInputLoaded = true
        store.history = [decision("priority", now: now)]
        store.requiredInputs = [decision("auto", now: now, deadline: now.addingTimeInterval(60))]
        await store.syncDecisionActivity()
        XCTAssertEqual(received.map(\.id), store.todaySnapshot(now: now).decisions.map(\.id))
        XCTAssertEqual(received.map(\.id), ["auto", "priority"])
    }

    func testCoverageOverrideDoesNotTurnAnOfflineSnapshotIntoAllClear() {
        let store = InboxStore(decisionAlertsEnabled: false)
        XCTAssertFalse(store.todaySnapshot(now: .now, coverageComplete: true).isAllClear)
    }

    func testNamedDesignColorsProvideLightAndDarkVariants() throws {
        let bundle = try XCTUnwrap(Bundle(identifier: "ai.hiboss.app"))
        let names = ["Ink", "Signal", "Live", "Settled", "Ground", "Surface", "SecondaryText",
                     "TertiaryText", "Hairline", "SignalSoft", "LiveSoft", "SettledSoft"]
        for name in names {
            let color = try XCTUnwrap(UIColor(named: name, in: bundle, compatibleWith: nil), name)
            XCTAssertNotEqual(color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)),
                              color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)), name)
        }
    }

    func testBothSuppliedSceneAssetsLoad() throws {
        let bundle = try XCTUnwrap(Bundle(identifier: "ai.hiboss.app"))
        for name in ["island-day", "island-night"] {
            let scene = try XCTUnwrap(UIImage(named: name, in: bundle, compatibleWith: nil))
            XCTAssertGreaterThan(scene.size.width, 0)
            XCTAssertGreaterThan(scene.size.height, 0)
        }
    }

    func testOptionsShareRowsUntilTheNextChoiceDoesNotFit() {
        let frames = DecisionOptionFlow.frames(
            sizes: [CGSize(width: 80, height: 44), CGSize(width: 100, height: 58),
                    CGSize(width: 90, height: 44)], width: 200
        )
        XCTAssertEqual(frames, [CGRect(x: 0, y: 0, width: 80, height: 58),
                                CGRect(x: 88, y: 0, width: 100, height: 58),
                                CGRect(x: 0, y: 66, width: 90, height: 44)])
    }

    func testLargeOptionsUseTheAvailableWidthAndSeparateRows() {
        let frames = DecisionOptionFlow.frames(
            sizes: [CGSize(width: 400, height: 100), CGSize(width: 160, height: 70)], width: 200
        )
        XCTAssertEqual(frames, [CGRect(x: 0, y: 0, width: 200, height: 100),
                                CGRect(x: 0, y: 108, width: 160, height: 70)])
    }

    func testOptionsThatExactlyFitStayOnTheSameRow() {
        let frames = DecisionOptionFlow.frames(
            sizes: [CGSize(width: 80, height: 44), CGSize(width: 112, height: 44)], width: 200
        )
        XCTAssertEqual(frames.map(\.minY), [0, 0])
        XCTAssertEqual(frames.last?.maxX, 200)
        XCTAssertTrue(DecisionOptionFlow.frames(sizes: [], width: 200).isEmpty)
    }

    private func decision(_ id: String, now: Date, deadline: Date? = nil) -> HistoryMessage {
        HistoryMessage(
            id: MessageID(rawValue: id), body: "Continue?", direction: "agent_to_boss",
            status: "delivered", priority: "high", mode: "blocking",
            metadata: MessageMetadata(options: ["Yes", "Hold"],
                                      defaultOption: deadline == nil ? nil : "Hold"),
            expiresAt: deadline?.ISO8601Format(), createdAt: now.ISO8601Format(),
            sessionId: "session-\(id)", sessionLabel: id
        )
    }
}
