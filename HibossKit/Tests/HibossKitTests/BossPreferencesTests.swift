// Coverage for boss notification preference Codable contracts.
// Exports: BossPreferencesTests validating notification preferences.
// Dependencies: XCTest and HibossKit preference domain models.

import XCTest
@testable import HibossKit

final class BossPreferencesTests: XCTestCase {
    func testDecodesPreferencesWithLegacyRouting() throws {
        let preferences = try decodePreferences(
            """
            {
              "routing": {
                "critical": ["discord", "telegram", "api"],
                "high": ["telegram"],
                "normal": ["discord"],
                "low": []
              },
              "quiet_hours": {
                "enabled": true,
                "start": "23:00",
                "end": "08:00",
                "timezone": "Asia/Shanghai",
                "days": [1, 2, 3, 4, 5],
                "critical_bypass": true
              },
              "decision_alerts": false
            }
            """
        )

        XCTAssertEqual(
            preferences.quietHours,
            QuietHours(
                enabled: true,
                start: "23:00",
                end: "08:00",
                timezone: "Asia/Shanghai",
                days: [1, 2, 3, 4, 5],
                criticalBypass: true
            )
        )
        XCTAssertEqual(preferences.decisionAlerts, false)
    }

    func testQuietHoursDecodeServerDefaultsAndFlatPrecedence() throws {
        let nested = try decodePreferences(#"{"quiet_hours":{"start":"11:00","end":"13:00"}}"#)
        XCTAssertEqual(nested.quietHours?.enabled, true)
        XCTAssertEqual(nested.quietHours?.timezone, "UTC")
        let flat = try decodePreferences(
            #"{"quiet_hours_start":"10:00","quiet_hours_end":"14:00","timezone":"Asia/Bangkok"}"#)
        XCTAssertEqual(flat.quietHours?.start, "10:00")
        XCTAssertEqual(flat.quietHours?.end, "14:00")
        XCTAssertEqual(flat.quietHours?.timezone, "Asia/Bangkok")
        let mixed = try decodePreferences(
            """
            {"quiet_hours_start":"10:00","timezone":"Asia/Bangkok",
             "quiet_hours":{"start":"11:00","end":"13:00","timezone":"UTC","enabled":false}}
            """)
        XCTAssertEqual(mixed.quietHours?.start, "10:00")
        XCTAssertEqual(mixed.quietHours?.end, "13:00")
        XCTAssertEqual(mixed.quietHours?.timezone, "UTC")
        XCTAssertEqual(mixed.quietHours?.enabled, false)
    }

    func testIncompleteQuietHoursDoNotInventAWindow() throws {
        let preferences = try decodePreferences(#"{"quiet_hours":{"start":"11:00"}}"#)
        XCTAssertFalse(MessageAlertPolicy.isQuiet(preferences.quietHours,
            at: Date(timeIntervalSince1970: 1_792_584_000)))
    }

    func testDecodesEmptyPayload() throws {
        let preferences = try decodePreferences("{}")

        XCTAssertNil(preferences.quietHours)
    }

    func testDecodesNullQuietHours() throws {
        let preferences = try decodePreferences(
            #"{"routing":true,"quiet_hours":null}"#
        )

        XCTAssertNil(preferences.quietHours)
    }

    func testDecodesDisabledQuietHours() throws {
        let preferences = try decodePreferences(
            """
            {
              "quiet_hours": {
                "enabled": false,
                "start": "23:00",
                "end": "08:00",
                "timezone": "Asia/Shanghai",
                "days": [],
                "critical_bypass": false
              }
            }
            """
        )

        XCTAssertEqual(preferences.quietHours?.enabled, false)
    }

    func testEncodesRoundTrip() throws {
        let preferences = BossPreferences(
            quietHours: QuietHours(
                enabled: true,
                start: "23:00",
                end: "08:00",
                timezone: "Asia/Shanghai",
                days: [1, 2, 3, 4, 5],
                criticalBypass: true
            ),
            decisionAlerts: true
        )

        let data = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(BossPreferences.self, from: data)

        XCTAssertEqual(decoded, preferences)
    }

    private func decodePreferences(_ json: String) throws -> BossPreferences {
        try JSONDecoder().decode(BossPreferences.self, from: Data(json.utf8))
    }
}
