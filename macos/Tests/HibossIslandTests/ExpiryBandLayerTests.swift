// Verifies wall-clock resynchronization and native expiry layer behavior.
// Exports: ExpiryBandLayerTests.
// Dependencies: AppKit, QuartzCore, XCTest, and ExpiryBandView.

import AppKit
import QuartzCore
import XCTest
@testable import HibossIsland

@MainActor
final class ExpiryBandLayerTests: XCTestCase {
    func testResynchronizationUsesWallClockInsteadOfPresentationLayer() throws {
        let now = Date()
        let view = ExpiryBandView(progress: ExpiryProgress(startedAt: now.addingTimeInterval(-80),
            expiresAt: now.addingTimeInterval(20)), surfaceStyle: .island)
        view.resynchronize()
        let drain = try XCTUnwrap(view.stroke.animation(forKey: "drain") as? CABasicAnimation)
        XCTAssertEqual(try XCTUnwrap(drain.fromValue as? Double), 0.2, accuracy: 0.01)
        XCTAssertEqual(drain.duration, 20, accuracy: 0.1)
        view.progress = ExpiryProgress(startedAt: now.addingTimeInterval(-200),
            expiresAt: now.addingTimeInterval(-100))
        view.resynchronize()
        XCTAssertNil(view.stroke.animation(forKey: "drain"))
        XCTAssertEqual(view.stroke.strokeEnd, 0)
    }

    func testRenewalRestartsFullAndSchedulesUrgencyThresholds() throws {
        let now = Date()
        let view = ExpiryBandView(progress: ExpiryProgress(startedAt: now,
            expiresAt: now.addingTimeInterval(100)), surfaceStyle: .window)
        view.resynchronize()
        let drain = try XCTUnwrap(view.stroke.animation(forKey: "drain") as? CABasicAnimation)
        XCTAssertEqual(try XCTUnwrap(drain.fromValue as? Double), 1, accuracy: 0.01)
        let colors = try XCTUnwrap(view.stroke.animation(forKey: "strokeColor") as? CAKeyframeAnimation)
        let times = try XCTUnwrap(colors.keyTimes)
        XCTAssertEqual(times.count, 4)
        XCTAssertEqual(times[1].doubleValue, 0.6, accuracy: 0.01)
        XCTAssertEqual(times[2].doubleValue, 0.85, accuracy: 0.01)
        XCTAssertEqual(colors.calculationMode, .discrete)
        XCTAssertNil(view.hitTest(.zero))
        XCTAssertEqual(view.intrinsicContentSize.height, NSView.noIntrinsicMetric)
    }

    func testWakeNotificationResynchronizesExpiredAnimation() {
        let now = Date()
        let view = ExpiryBandView(progress: ExpiryProgress(startedAt: now,
            expiresAt: now.addingTimeInterval(100)), surfaceStyle: .island)
        view.resynchronize()
        view.progress = ExpiryProgress(startedAt: now.addingTimeInterval(-200),
            expiresAt: now.addingTimeInterval(-100))
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        XCTAssertNil(view.stroke.animation(forKey: "drain"))
    }
}
