// Logic tests for the native macOS Settings scene.
// Covers: pane order, quiet-hours validation, and sound mapping.
// Dependencies: XCTest, HibossKit preferences, AppSettings, and isolated defaults.

import Foundation
import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class SettingsLogicTests: XCTestCase {
    func testSignInIsNeededOnlyAfterTheStoredTokenIsReadAndAbsent() async throws {
        let suite = "SettingsLogicTests.signIn.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults, keychain: StubTokenStore())
        XCTAssertFalse(settings.needsSignIn, "a launch never shows first run before the keychain read")
        await settings.loadToken()
        XCTAssertTrue(settings.needsSignIn)
    }

    func testAboutLinksToTheProjectSite() {
        XCTAssertEqual(AboutSettingsPane.projectURL?.absoluteString, "https://hiboss.org")
    }

    func testSettingsPanesAppearInDesignOrder() {
        XCTAssertEqual(SettingsPane.allCases.map(\.title), [
            L("General"),
            L("Connection"),
            L("Devices"),
            L("Notifications"),
            L("Quiet Hours"),
            L("Presentation"),
            L("System & Doctor"),
            L("About"),
        ])
    }

    func testSelectsConnectionWhenRequestedPaneIsUnavailable() {
        XCTAssertEqual(SettingsPreferencesLogic.selectedPane(nil), .connection)
        XCTAssertEqual(
            SettingsPreferencesLogic.selectedPane(.quietHours, available: [.connection]),
            .connection
        )
    }

    func testSelectsRequestedPaneWhenAvailable() {
        XCTAssertEqual(SettingsPreferencesLogic.selectedPane(.quietHours), .quietHours)
    }

    func testQuietHoursFallsBackToDefaultWhenServerHasNone() {
        let quietHours = SettingsPreferencesLogic.quietHours(from: BossPreferences())

        XCTAssertEqual(quietHours.start, "22:00")
        XCTAssertEqual(quietHours.end, "07:00")
        XCTAssertEqual(quietHours.days, [1, 2, 3, 4, 5, 6, 7])
        XCTAssertTrue(quietHours.criticalBypass)
    }

    func testQuietHoursUsesServerValueWhenPresent() {
        let quietHours = QuietHours(
            enabled: true,
            start: "09:00",
            end: "17:00",
            timezone: "UTC",
            days: [1],
            criticalBypass: false
        )

        XCTAssertEqual(
            SettingsPreferencesLogic.quietHours(from: BossPreferences(quietHours: quietHours)),
            quietHours
        )
    }

    func testDaySelectorRemovesAnExistingDayAndKeepsTheRestSorted() {
        let quietHours = QuietHours(
            enabled: true,
            start: "22:00",
            end: "07:00",
            timezone: "UTC",
            days: [1, 3, 5],
            criticalBypass: true
        )

        let next = SettingsPreferencesLogic.toggledDay(3, in: quietHours)

        XCTAssertEqual(next.days, [1, 5])
    }

    func testDaySelectorAddsAMissingDayAndKeepsTheRestSorted() {
        let quietHours = QuietHours(
            enabled: true,
            start: "22:00",
            end: "07:00",
            timezone: "UTC",
            days: [1, 5],
            criticalBypass: true
        )

        let next = SettingsPreferencesLogic.toggledDay(3, in: quietHours)

        XCTAssertEqual(next.days, [1, 3, 5])
    }

    func testQuietHoursClockFormattingRoundTripsHourAndMinute() {
        let reference = Calendar.current.date(
            from: DateComponents(year: 2026, month: 7, day: 20, hour: 12, minute: 0)
        ) ?? .now
        let date = QuietHoursClockFormatting.date(fromClock: "22:05", reference: reference)
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)

        XCTAssertEqual(components.hour, 22)
        XCTAssertEqual(components.minute, 5)
        XCTAssertEqual(QuietHoursClockFormatting.clockString(from: date), "22:05")
    }

    func testQuietHoursClockFormattingFallsBackForMalformedInput() {
        let reference = Calendar.current.date(
            from: DateComponents(year: 2026, month: 7, day: 20, hour: 12, minute: 0)
        ) ?? .now
        let date = QuietHoursClockFormatting.date(fromClock: "noon", reference: reference)
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)

        XCTAssertEqual(components.hour, 0)
        XCTAssertEqual(components.minute, 0)
        XCTAssertEqual(QuietHoursClockFormatting.weekdayTitle(dayIndex: 1), L("Monday"))
    }

    func testClockTimeValidationAcceptsStrictTwentyFourHourTimes() {
        XCTAssertTrue(SettingsPreferencesLogic.isValidClockTime("00:00"))
        XCTAssertTrue(SettingsPreferencesLogic.isValidClockTime("23:59"))
    }

    func testClockTimeValidationRejectsMalformedOrOutOfRangeTimes() {
        XCTAssertFalse(SettingsPreferencesLogic.isValidClockTime("7:00"))
        XCTAssertFalse(SettingsPreferencesLogic.isValidClockTime("24:00"))
        XCTAssertFalse(SettingsPreferencesLogic.isValidClockTime("12:60"))
        XCTAssertFalse(SettingsPreferencesLogic.isValidClockTime("noon"))
    }

    func testValidatedQuietHoursReturnsTheValidSchedule() throws {
        let quietHours = SettingsPreferencesLogic.defaultQuietHours(timezone: "UTC")

        let validated = try SettingsPreferencesLogic.validatedQuietHours(quietHours).get()

        XCTAssertEqual(validated, quietHours)
    }

    func testValidatedQuietHoursReportsTheInvalidTimeField() {
        let quietHours = QuietHours(
            enabled: true,
            start: "9:00",
            end: "07:00",
            timezone: "UTC",
            days: [1],
            criticalBypass: true
        )

        XCTAssertEqual(
            SettingsPreferencesLogic.validatedQuietHours(quietHours),
            .failure(.invalidTime("start"))
        )
    }

    func testUpdatingQuietHoursPreservesAlertPreferences() {
        let preferences = BossPreferences(privatePush: true, decisionAlerts: false)
        let quietHours = SettingsPreferencesLogic.defaultQuietHours(timezone: "UTC")

        let mapped = SettingsPreferencesLogic.preferences(preferences, byUpdating: quietHours)

        XCTAssertEqual(mapped.privatePush, true)
        XCTAssertEqual(mapped.decisionAlerts, false)
        XCTAssertEqual(mapped.quietHours, quietHours)
    }

    func testValidationMessageSurfacesInvalidQuietHours() {
        let quietHours = QuietHours(
            enabled: true,
            start: "22:00",
            end: "7:00",
            timezone: "UTC",
            days: [1],
            criticalBypass: true
        )

        XCTAssertEqual(
            SettingsPreferencesLogic.validationMessage(for: BossPreferences(quietHours: quietHours)),
            L("Enter a valid \(L("end")) time as HH:mm.")
        )
    }

    func testPerPrioritySoundDefaultsAreClientSideOnly() throws {
        let defaults = isolatedDefaults()
        let settings = AppSettings(defaults: defaults, keychain: StubTokenStore())
        let preferences = BossPreferences(privatePush: true)

        settings.setSound(.submarine, for: .critical)
        let encoded = try JSONEncoder().encode(preferences)
        let payload = String(decoding: encoded, as: UTF8.self)

        XCTAssertEqual(settings.sound(for: .critical), .submarine)
        XCTAssertFalse(payload.contains("Submarine"))
    }

    func testPerPrioritySoundRestoresFromUserDefaults() {
        let defaults = isolatedDefaults()
        let initial = AppSettings(defaults: defaults, keychain: StubTokenStore())

        initial.setSound(.funk, for: .high)
        let restored = AppSettings(defaults: defaults, keychain: StubTokenStore())

        XCTAssertEqual(restored.sound(for: .high), .funk)
    }

    func testBannerDisplayChoicePersistsAndUsesWindowPresentationPath() {
        let defaults = isolatedDefaults()
        let initial = AppSettings(defaults: defaults, keychain: StubTokenStore())

        initial.optionDisplayMode = .banner
        let restored = AppSettings(defaults: defaults, keychain: StubTokenStore())

        XCTAssertEqual(restored.optionDisplayMode, .banner)
        XCTAssertEqual(restored.presentationMode, .window)
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "SettingsLogicTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }
}

private struct StubTokenStore: TokenStoring {
    func read() throws -> String? { nil }
    func write(_ token: String) throws {}
}
