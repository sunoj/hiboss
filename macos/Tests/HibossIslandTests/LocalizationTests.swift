// Tests that catalog lookups resolve from the package bundle and values format per locale.
// Covers: plural variations, new catalog keys, message detail names, and date fallbacks.
// Dependencies: XCTest, HibossKit HistoryMessage, and HibossIsland L10n helpers.

import HibossKit
import XCTest
@testable import HibossIsland

final class LocalizationTests: XCTestCase {
    func testCountedStringUsesEnglishPluralVariations() throws {
        XCTAssertEqual(try english("View all \(1) decisions"), "View all 1 decision")
        XCTAssertEqual(try english("View all \(3) decisions"), "View all 3 decisions")
    }

    func testExtractedKeysResolveFromTheCompiledCatalog() throws {
        XCTAssertEqual(try english("Chooses \("Ship") in \("5s")"), "Chooses Ship in 5s")
        XCTAssertEqual(try english("Captured submission"), "Captured submission")
        XCTAssertEqual(try english("That decision is no longer available."),
                       "That decision is no longer available.")
        XCTAssertEqual(try english("Couldn't send your reply. Try again."), "Couldn't send your reply. Try again.")
    }

    func testCreatedTimestampFormatsPerLocaleAndKeepsUnparseableValues() throws {
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let english = HistoryTimestamp.localDateTime(
            from: "2026-07-15 10:00:00", locale: Locale(identifier: "en_US"), timeZone: utc)
        let japanese = HistoryTimestamp.localDateTime(
            from: "2026-07-15 10:00:00", locale: Locale(identifier: "ja_JP"), timeZone: utc)
        // The year is left out: it follows the user's calendar setting (e.g. Buddhist).
        XCTAssertTrue(english.contains("Jul 15") && english.contains("10:00"), english)
        XCTAssertTrue(japanese.contains("7月15日") && japanese.contains("10:00"), japanese)
        XCTAssertEqual(HistoryTimestamp.localDateTime(from: "someday"), "someday")
    }

    func testUnknownServerValuesStayAsSent() {
        XCTAssertEqual(message(status: "queued", priority: "urgent").historyStatusName, "queued")
        XCTAssertEqual(message(status: "queued", priority: "urgent").historyPriorityName, "Urgent")
        XCTAssertEqual(message(status: "delivered", priority: "").historyPriorityName, "")
    }

    func testSoundNamesReadThroughTheCatalog() {
        XCTAssertEqual(OptionSound.ping.label, L("Ping"))
        XCTAssertEqual(OptionSound.allCases.map(\.label).count, Set(OptionSound.allCases.map(\.label)).count)
    }

    private func english(_ key: String.LocalizationValue) throws -> String {
        let path = try XCTUnwrap(appResourceBundle.path(forResource: "en", ofType: "lproj"))
        let bundle = try XCTUnwrap(Bundle(path: path))
        return String(localized: key, bundle: bundle, locale: Locale(identifier: "en_US"))
    }

    private func message(status: String, priority: String) -> HistoryMessage {
        HistoryMessage(id: "l10n", body: "Body", agentName: "Agent", direction: "agent_to_boss",
                       status: status, priority: priority, metadata: nil, createdAt: "")
    }
}
