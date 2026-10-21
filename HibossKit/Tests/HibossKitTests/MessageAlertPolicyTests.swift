// Pins the client copy of the server's boss push rules: tiers, overrides, decision alerts, quiet hours.
// Exports: MessageAlertPolicyTests.
// Dependencies: XCTest and HibossKit MessageAlertPolicy / BossPreferences.

import XCTest
@testable import HibossKit

final class MessageAlertPolicyTests: XCTestCase {
    /// 2026-10-21 12:00 UTC.
    private let noon = Date(timeIntervalSince1970: 1_792_584_000)

    func testDefaultTiersSkipLowAndKeepNormalSilent() {
        let none = BossPreferences()
        XCTAssertNil(MessageAlertPolicy.messageAlert(priority: "low", preferences: none, now: noon))
        XCTAssertEqual(MessageAlertPolicy.messageAlert(priority: "normal", preferences: none, now: noon),
                       MessageAlert(sound: false, level: .passive))
        XCTAssertEqual(MessageAlertPolicy.messageAlert(priority: "high", preferences: none, now: noon),
                       MessageAlert(sound: true, level: .active))
        XCTAssertEqual(MessageAlertPolicy.messageAlert(priority: "critical", preferences: none, now: noon),
                       MessageAlert(sound: true, level: .timeSensitive))
    }

    func testPerPriorityOverridesReplaceTheTier() {
        let prefs = BossPreferences(push: [
            .low: PushRule(deliver: true, sound: true, level: .active),
            .high: PushRule(deliver: false, sound: true, level: .active),
        ])
        XCTAssertEqual(MessageAlertPolicy.messageAlert(priority: "low", preferences: prefs, now: noon),
                       MessageAlert(sound: true, level: .active))
        XCTAssertNil(MessageAlertPolicy.messageAlert(priority: "high", preferences: prefs, now: noon))
    }

    func testQuietHoursHoldNonUrgentMessagesOnly() {
        let quiet = BossPreferences(quietHours: QuietHours(enabled: true, start: "11:00", end: "13:00",
            timezone: "UTC", days: [], criticalBypass: false))
        XCTAssertNil(MessageAlertPolicy.messageAlert(priority: "normal", preferences: quiet, now: noon))
        XCTAssertNotNil(MessageAlertPolicy.messageAlert(priority: "high", preferences: quiet, now: noon))
        XCTAssertNotNil(MessageAlertPolicy.messageAlert(priority: "normal", preferences: quiet,
            now: noon.addingTimeInterval(2 * 3600)))
        let off = BossPreferences(quietHours: QuietHours(enabled: false, start: "11:00", end: "13:00",
            timezone: "UTC", days: [], criticalBypass: false))
        XCTAssertNotNil(MessageAlertPolicy.messageAlert(priority: "normal", preferences: off, now: noon))
    }

    func testQuietHoursWrapMidnightInTheBossTimeZone() {
        let night = QuietHours(enabled: true, start: "22:00", end: "08:00", timezone: "Asia/Shanghai",
            days: [], criticalBypass: true)
        XCTAssertFalse(MessageAlertPolicy.isQuiet(night, at: noon), "20:00 in Shanghai")
        XCTAssertTrue(MessageAlertPolicy.isQuiet(night, at: noon.addingTimeInterval(3 * 3600)), "23:00")
        XCTAssertTrue(MessageAlertPolicy.isQuiet(night, at: noon.addingTimeInterval(10 * 3600)), "06:00")
        let same = QuietHours(enabled: true, start: "08:00", end: "08:00", timezone: "UTC",
            days: [], criticalBypass: true)
        XCTAssertFalse(MessageAlertPolicy.isQuiet(same, at: noon))
    }

    func testDecisionAlertsAreLoudUnlessTurnedOff() {
        XCTAssertEqual(MessageAlertPolicy.decisionAlert(priority: "low", preferences: BossPreferences()),
                       MessageAlert(sound: true, level: .active))
        let off = BossPreferences(decisionAlerts: false)
        XCTAssertNil(MessageAlertPolicy.decisionAlert(priority: "low", preferences: off))
        XCTAssertEqual(MessageAlertPolicy.decisionAlert(priority: "normal", preferences: off),
                       MessageAlert(sound: false, level: .passive))
    }
}
