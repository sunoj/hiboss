// Unit coverage for ProgressModelVendor prefix mapping.
// Exports: ProgressModelVendorTests.
// Dependencies: XCTest and HibossKit.

import XCTest
@testable import HibossKit

final class ProgressModelVendorTests: XCTestCase {
    func testMapsKnownPrefixes() {
        XCTAssertEqual(ProgressModelVendor.from(model: "claude-opus-5"), .anthropic)
        XCTAssertEqual(ProgressModelVendor.from(model: "GPT-4o"), .openAI)
        XCTAssertEqual(ProgressModelVendor.from(model: "o3-mini"), .openAI)
        XCTAssertEqual(ProgressModelVendor.from(model: "gemini-2.5-pro"), .google)
        XCTAssertEqual(ProgressModelVendor.from(model: "grok-3"), .xAI)
    }

    func testUnknownAndEmptyStayNeutral() {
        XCTAssertEqual(ProgressModelVendor.from(model: nil), .unknown)
        XCTAssertEqual(ProgressModelVendor.from(model: ""), .unknown)
        XCTAssertEqual(ProgressModelVendor.from(model: "opus-custom"), .unknown)
        XCTAssertEqual(ProgressModelVendor.from(model: "deepseek-r1"), .unknown)
    }

    func testMonogramLetters() {
        XCTAssertEqual(ProgressModelVendor.anthropic.monogram, "A")
        XCTAssertEqual(ProgressModelVendor.openAI.monogram, "O")
        XCTAssertEqual(ProgressModelVendor.google.monogram, "G")
        XCTAssertEqual(ProgressModelVendor.xAI.monogram, "X")
        XCTAssertEqual(ProgressModelVendor.unknown.monogram, "?")
    }
}
