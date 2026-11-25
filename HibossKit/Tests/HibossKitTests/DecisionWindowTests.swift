// Countdown windows for pending decisions: the remaining fraction and the soonest per session.
// Covers DecisionWindow and TodaySession.decisionWindow through SessionDirectory.
// Dependencies: XCTest, HibossKit, and TodayTestSupport fixtures.

import HibossKit
import XCTest

final class DecisionWindowTests: XCTestCase {
    private let now = TodayTestSupport.now

    func testRemainingFractionRunsFromOneToZeroAndClamps() {
        let window = DecisionWindow(start: now, deadline: now.addingTimeInterval(100))
        XCTAssertEqual(window.remainingFraction(at: now), 1)
        XCTAssertEqual(window.remainingFraction(at: now.addingTimeInterval(25)), 0.75, accuracy: 1e-9)
        XCTAssertEqual(window.remainingFraction(at: now.addingTimeInterval(100)), 0)
        XCTAssertEqual(window.remainingFraction(at: now.addingTimeInterval(500)), 0)
        XCTAssertEqual(window.remainingFraction(at: now.addingTimeInterval(-50)), 1)
        XCTAssertEqual(DecisionWindow(start: now, deadline: now).remainingFraction(at: now), 0)
        XCTAssertTrue(window.isLive(at: now.addingTimeInterval(99)))
        XCTAssertFalse(window.isLive(at: now.addingTimeInterval(100)))
    }

    func testNeedsYouSessionCarriesItsSoonestDeadline() {
        let late = TodayTestSupport.message("late", age: 600, options: ["Yes"], expiresIn: 1200)
        let soon = TodayTestSupport.message("soon", age: 60, options: ["Yes"], expiresIn: 240)
        let open = TodayTestSupport.message("open", session: "no-deadline", options: ["Yes"])
        let inputs = [late, soon, open]
        let directory = SessionDirectory(history: inputs, requiredInputs: inputs, now: now)
        let session = directory.needsYou.first { $0.id == "session" }
        XCTAssertEqual(session?.decisionWindow,
                       DecisionWindow(start: now.addingTimeInterval(-60), deadline: now.addingTimeInterval(240)))
        XCTAssertNotNil(directory.needsYou.first { $0.id == "no-deadline" })
        XCTAssertNil(directory.needsYou.first { $0.id == "no-deadline" }?.decisionWindow)
    }
}
