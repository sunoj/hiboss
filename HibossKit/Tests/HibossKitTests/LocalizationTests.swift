// Localization tests for HibossKit user-facing error and label copy.
// Exports: LocalizationTests covering API errors and priority titles.
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

    func testConnectionStateLabelsMatchCatalog() {
        XCTAssertEqual(ConnectionState.disconnected.label, kitL("Disconnected"))
        XCTAssertEqual(ConnectionState.connected.label, kitL("Listening"))
    }
}
