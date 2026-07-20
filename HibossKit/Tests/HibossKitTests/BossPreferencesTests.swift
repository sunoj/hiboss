// Coverage for boss notification preference Codable contracts.
// Exports: BossPreferencesTests validating routing and quiet hours payloads.
// Dependencies: XCTest and HibossKit preference domain models.

import XCTest
@testable import HibossKit

final class BossPreferencesTests: XCTestCase {
    func testDecodesFullPayload() throws {
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
              }
            }
            """
        )

        XCTAssertEqual(preferences.routing?[.critical], [.discord, .telegram, .api])
        XCTAssertEqual(preferences.routing?[.high], [.telegram])
        XCTAssertEqual(preferences.routing?[.normal], [.discord])
        XCTAssertEqual(preferences.routing?[.low], [])
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
    }

    func testDecodesEmptyPayload() throws {
        let preferences = try decodePreferences("{}")

        XCTAssertNil(preferences.routing)
        XCTAssertNil(preferences.quietHours)
    }

    func testDecodesNullQuietHours() throws {
        let preferences = try decodePreferences(
            #"{"routing":{"critical":["discord"]},"quiet_hours":null}"#
        )

        XCTAssertEqual(preferences.routing?[.critical], [.discord])
        XCTAssertNil(preferences.quietHours)
    }

    func testSkipsUnknownChannelString() throws {
        let preferences = try decodePreferences(
            #"{"routing":{"critical":["discord","sms","api"]}}"#
        )

        XCTAssertEqual(preferences.routing?[.critical], [.discord, .api])
    }

    func testDecodesAbsentRouting() throws {
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

        XCTAssertNil(preferences.routing)
        XCTAssertEqual(preferences.quietHours?.enabled, false)
    }

    func testEncodesRoundTrip() throws {
        let preferences = BossPreferences(
            routing: [
                .critical: [.discord, .telegram, .api],
                .high: [.telegram],
                .normal: [.discord],
                .low: [],
            ],
            quietHours: QuietHours(
                enabled: true,
                start: "23:00",
                end: "08:00",
                timezone: "Asia/Shanghai",
                days: [1, 2, 3, 4, 5],
                criticalBypass: true
            )
        )

        let data = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(BossPreferences.self, from: data)

        XCTAssertEqual(decoded, preferences)
    }

    private func decodePreferences(_ json: String) throws -> BossPreferences {
        try JSONDecoder().decode(BossPreferences.self, from: Data(json.utf8))
    }
}
