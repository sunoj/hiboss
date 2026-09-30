// Localization tests for HibossKit user-facing error and label copy.
// Exports: LocalizationTests covering API errors, labels, plurals, and bundle lookup.
// Dependencies: XCTest and HibossKit.

import XCTest
@testable import HibossKit

final class LocalizationTests: XCTestCase {
    func testAPIErrorMessagesAreNonEmpty() {
        XCTAssertEqual(
            HibossAPIError.invalidResponse.errorDescription,
            kitL("The server returned an invalid response.")
        )
        XCTAssertEqual(
            HibossAPIError.requestFailed(status: 401, message: "").errorDescription,
            kitL("That Boss Token was rejected. Check the token and try again.")
        )
        XCTAssertEqual(
            HibossAPIError.requestFailed(status: 500, message: "").errorDescription,
            kitL("Server request failed (HTTP \(500)).")
        )
    }

    func testPriorityTitlesMatchCatalog() {
        XCTAssertEqual(MessagePriority.critical.localizedTitle, kitL("Critical"))
        XCTAssertEqual(MessagePriority.low.localizedTitle, kitL("Low"))
    }

    func testZhHansCatalogResolvesThroughPackageBundle() throws {
        let url = try XCTUnwrap(kitResourceBundle.url(forResource: "zh-Hans", withExtension: "lproj"))
        let zhHans = try XCTUnwrap(Bundle(url: url))
        XCTAssertEqual(zhHans.localizedString(forKey: "Cancel", value: nil, table: nil), "取消")
        XCTAssertEqual(zhHans.localizedString(forKey: "Devices", value: nil, table: nil), "设备")
        XCTAssertEqual(zhHans.localizedString(forKey: "Server request failed (HTTP %lld).", value: nil, table: nil),
                       "服务器请求失败（HTTP %lld）。")
        XCTAssertEqual(Bundle.main.localizedString(forKey: "Cancel", value: nil, table: nil), "Cancel",
                       "Bundle.main must not carry the package catalog")
    }

    func testCountedStringsUsePluralVariations() {
        XCTAssertEqual(kitL("\(1) fields"), "1 field")
        XCTAssertEqual(kitL("\(3) fields"), "3 fields")
        XCTAssertEqual(kitL("\(1) more rows in panel"), "1 more row in panel")
    }

    func testPanelStatusCopyResolvesFromCatalog() {
        XCTAssertEqual(PanelTaskState.completed.title, "Completed")
        XCTAssertEqual(PanelFreshness.awaitingData.title, "Awaiting data")
        XCTAssertEqual(PanelValue.bool(true).displayText, "On")
        XCTAssertEqual(PanelValue.number(1234.5).formattedText, 1234.5.formatted())
        XCTAssertEqual(PanelValue.number(1234.5).displayText, "1234.5")
    }

    func testConnectionStateLabelsMatchCatalog() {
        XCTAssertEqual(ConnectionState.disconnected.label, kitL("Disconnected"))
        XCTAssertEqual(ConnectionState.connected.label, kitL("Listening"))
    }
}
