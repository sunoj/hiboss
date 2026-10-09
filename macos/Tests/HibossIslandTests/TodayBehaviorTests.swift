// Verifies v4 projections, truthful health/coverage, default copy, and bundled vector assets.
// Exports: TodayBehaviorTests; ordering is compared directly with HibossKit.
// Dependencies: XCTest, AppKit, HibossKit, and TodayProjection.

import AppKit
import HibossKit
import XCTest
@testable import HibossIsland

final class TodayBehaviorTests: XCTestCase {
    private let now = AttentionTestSupport.now

    func testWindowAndIslandFollowSharedRankingIncludingTextOnlyBlockingMessages() {
        let text = HistoryMessage(id: "text", body: "Describe the rollback plan", agentName: "Agent",
            direction: "agent_to_boss", status: "delivered", priority: "normal", mode: "blocking",
            createdAt: AttentionTestSupport.iso(now), sessionId: "session", sessionStatus: "waiting")
        let choice = AttentionTestSupport.ask(id: "choice", options: ["Ship"], now: now)
        let history = [choice, text]
        let snapshot = OverviewSnapshot(history: history, live: nil, now: now, requiredInputs: history)
        XCTAssertEqual(snapshot.attention, AttentionModel.items(from: history, now: now))
        XCTAssertEqual(snapshot.attention.first?.id, "text")
        XCTAssertEqual(IslandAttention.presentation(live: nil, history: history, now: now)?.message.id,
            "text")
        XCTAssertEqual(snapshot.today.sessionDirectory.needsYou.map(\.id), ["session", "choice"])
    }

    func testAllClearRequiresLiveHealthAndCompleteCoverage() {
        for health in [TodayHealth.loading, .connecting, .offline(since: now)] {
            XCTAssertFalse(OverviewSnapshot(history: [], live: nil, now: now,
                health: health, coverageComplete: true).today.isAllClear)
        }
        XCTAssertFalse(OverviewSnapshot(history: [], live: nil, now: now,
            health: .live(checkedAt: now), coverageComplete: false).today.isAllClear)
        XCTAssertTrue(OverviewSnapshot(history: [], live: nil, now: now,
            health: .live(checkedAt: now), coverageComplete: true).today.isAllClear)
    }

    func testFullHistoryPageCannotProveCoverage() {
        let page = (0..<AppConstants.API.historyLimit).map {
            AttentionTestSupport.ask(id: MessageID(rawValue: "message-\($0)"), options: [], now: now)
        }
        XCTAssertFalse(TodayProjection.coverage(history: page, state: .loaded))
        XCTAssertTrue(TodayProjection.coverage(history: Array(page.dropLast()), state: .loaded))
        XCTAssertFalse(TodayProjection.coverage(history: [], state: .loading))
        XCTAssertFalse(TodayProjection.coverage(history: [], state: .failed("unavailable")))
    }

    func testKnownReplyConflictWithdrawsStaleHistoryWithoutChangingOtherDecisions() {
        let history = [AttentionTestSupport.ask(id: "closed", options: ["Ship"], now: now),
                       AttentionTestSupport.ask(id: "open", options: ["Wait"], now: now)]
        let withdrawn = TodayProjection.withdrawn(feedback: ["closed": .alreadyResolved, "open": .failed("")])
        let snapshot = OverviewSnapshot(history: history, live: nil, now: now, withdrawn: withdrawn,
            requiredInputs: history)
        XCTAssertEqual(snapshot.attention.map(\.id), ["open"])
        XCTAssertEqual(IslandAttention.presentation(live: nil, history: history,
            now: now, withdrawn: withdrawn)?.message.id, "open")
        XCTAssertEqual(snapshot.messages(for: .category(.all)).count, 2)
    }

    @MainActor
    func testMenuBarLabelUsesTheAppIconAndOnlyOpenDecisionCount() {
        let button = NSButton()
        AppIdentity.configure(button, count: 2)
        XCTAssertEqual(button.title.trimmingCharacters(in: .whitespaces), "2")
        XCTAssertEqual(button.image?.size, NSSize(width: 18, height: 18))
        AppIdentity.configure(button, count: 0)
        XCTAssertTrue(button.title.isEmpty)
        XCTAssertNotNil(button.image)
    }

    @MainActor
    func testHealthAndCoverageChangesInvalidateTheCachedSnapshot() {
        let store = OverviewStore()
        store.update(history: [], live: nil, now: now)
        XCTAssertFalse(store.snapshot.today.isAllClear)
        store.update(history: [], live: nil, now: now, health: .live(checkedAt: now), coverageComplete: true)
        XCTAssertTrue(store.snapshot.today.isAllClear)
        store.update(history: [], live: nil, now: now, health: .connecting, coverageComplete: true)
        XCTAssertFalse(store.snapshot.today.isAllClear)
    }

    func testDefaultCopyExplicitlyDeniesApprovalWithAndWithoutDeadline() {
        XCTAssertEqual(DecisionDefaultLine.text(option: "Hold",
            expiresAt: now.addingTimeInterval(60), now: now),
            L("No answer in \("1m") picks “\("Hold")”. That is not approval."))
        XCTAssertEqual(DecisionDefaultLine.text(option: "Hold", expiresAt: nil, now: now),
            L("Default: “\("Hold")”. That is not approval."))
    }

    @MainActor
    func testNamedColoursAndOriginalVectorScenesAreBundled() throws {
        for name in ["Ink", "Signal", "Live", "Settled", "Ground", "Surface", "SecondaryText",
                     "TertiaryText", "Hairline", "SignalSoft", "LiveSoft", "SettledSoft"] {
            let colour = try XCTUnwrap(NSColor(named: name, bundle: appResourceBundle))
            for mode in [NSAppearance.Name.aqua, .darkAqua] {
                let appearance = try XCTUnwrap(NSAppearance(named: mode))
                appearance.performAsCurrentDrawingAppearance {
                    XCTAssertNotNil(colour.usingColorSpace(.deviceRGB))
                }
            }
        }
        for name in ["island-day", "island-night"] {
            let url = try XCTUnwrap(appResourceBundle.url(forResource: name, withExtension: "svg"))
            let image = try XCTUnwrap(NSImage(contentsOf: url))
            XCTAssertEqual(image.size, name == "island-day"
                ? NSSize(width: 600, height: 520) : NSSize(width: 358, height: 168))
            XCTAssertTrue(image.representations.contains { String(describing: type(of: $0)).contains("SVG") })
        }
        XCTAssertFalse(AppIdentity.icon.representations.isEmpty)
    }
}
