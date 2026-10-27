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
        XCTAssertEqual(MessageAlertPolicy.messageAlert(priority: "high", preferences: quiet, now: noon),
                       MessageAlert(sound: true, level: .active))
        XCTAssertEqual(MessageAlertPolicy.messageAlert(priority: "normal", preferences: quiet,
            now: noon.addingTimeInterval(2 * 3600)), MessageAlert(sound: false, level: .passive))
        let off = BossPreferences(quietHours: QuietHours(enabled: false, start: "11:00", end: "13:00",
            timezone: "UTC", days: [], criticalBypass: false))
        XCTAssertEqual(MessageAlertPolicy.messageAlert(priority: "normal", preferences: off, now: noon),
                       MessageAlert(sound: false, level: .passive))
    }

    func testQuietHoursWrapMidnightInTheBossTimeZone() {
        let night = QuietHours(enabled: true, start: "22:00", end: "08:00", timezone: "Asia/Shanghai",
            days: [], criticalBypass: true)
        // Hours after 20:00 in Shanghai: the quiet interval includes 22:00 and excludes 08:00.
        for (hours, expected) in [(0, false), (2, true), (3, true), (10, true), (12, false)] {
            let date = noon.addingTimeInterval(Double(hours) * 3600)
            XCTAssertEqual(MessageAlertPolicy.isQuiet(night, at: date), expected, "offset: \(hours)h")
        }
        let same = QuietHours(enabled: true, start: "08:00", end: "08:00", timezone: "UTC",
            days: [], criticalBypass: true)
        XCTAssertFalse(MessageAlertPolicy.isQuiet(same, at: noon))
    }

    func testQuietHoursHoldNonUrgentDecisions() {
        let preferences = BossPreferences(quietHours: QuietHours(enabled: true,
            start: "00:00", end: "23:59", timezone: "UTC", days: [], criticalBypass: true))
        for priority in ["normal", "low"] {
            XCTAssertNil(MessageAlertPolicy.decisionAlert(priority: priority, preferences: preferences, now: noon))
        }
        for (priority, level) in [("high", PushLevel.active), ("critical", .timeSensitive)] {
            XCTAssertEqual(MessageAlertPolicy.decisionAlert(priority: priority,
                preferences: preferences, now: noon), MessageAlert(sound: true, level: level))
        }
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
