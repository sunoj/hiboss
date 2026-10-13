// Verifies one Box title/subtitle rule shared by rows, details, and session references.
// Exports: BoxTitlePresentationTests covering notes, filenames, and unnamed media.
// Dependencies: XCTest, HibossKit, and synthetic BoxBrowserFixtures.

import HibossKit
import XCTest
@testable import HibossIsland

final class BoxTitlePresentationTests: XCTestCase {
    func testUnnamedMediaPromotesNoteFirstLineWithoutRepeatingIt() {
        for title in [nil, "", "  ", "Image", "image"] as [String?] {
            let item = BoxBrowserFixtures.item("image", kind: .image, text: title,
                note: "  Soil boring locations  \nSecond line with the measurements.")
            XCTAssertEqual(item.displayTitle, "Soil boring locations")
            XCTAssertEqual(item.summary, "Second line with the measurements.")
            XCTAssertEqual(item.detailNote, "Second line with the measurements.")
        }
    }

    func testSingleLineNoteIsNotRepeatedAndUntitledMediaKeepsKindFallback() {
        let item = BoxBrowserFixtures.item("image", kind: .image, note: "Road distance 1.3 m")
        XCTAssertEqual(item.displayTitle, "Road distance 1.3 m")
        XCTAssertEqual(item.summary, "")
        XCTAssertNil(item.detailNote)
        XCTAssertEqual(BoxBrowserFixtures.item("empty", kind: .image).displayTitle, L("Image"))
    }

    func testUserTitleAndFilenameTakePrecedenceOverNote() {
        for title in ["Foundation plan", "boring-results.jpeg"] {
            let item = BoxBrowserFixtures.item("named", kind: .image, text: title, note: "Measurements")
            XCTAssertEqual(item.displayTitle, title)
            XCTAssertEqual(item.summary, "Measurements")
            XCTAssertEqual(item.detailNote, "Measurements")
        }
        let link = BoxBrowserFixtures.item("link", kind: .link,
            url: "https://example.com/", note: "Reference")
        XCTAssertEqual(link.displayTitle, "https://example.com/")
        XCTAssertEqual(link.summary, "example.com")
    }

    func testPromotedNoteTitleKeepsItsEntireFirstLine() {
        let line = String(repeating: "Measurement ", count: 20).trimmingCharacters(in: .whitespaces)
        let item = BoxBrowserFixtures.item("long", kind: .image, note: line + "\nDetails")
        XCTAssertEqual(item.displayTitle, line)
        XCTAssertEqual(item.summary, "Details")
    }
}
