// Checks tolerant decoding and normalized lookup of option descriptions.
// Exports: OptionDescriptionTests for the shared metadata wire contract.
// Dependencies: XCTest and HibossKit.

import XCTest
@testable import HibossKit

final class OptionDescriptionTests: XCTestCase {
    func testDecodesValidEntriesAndIgnoresMalformedOrInvalidEntries() throws {
        let json = """
        {"options":[" A ","B"],"option_descriptions":[
          {"label":" A ","text":"  **Plain text**  "},
          {"label":"A","text":"duplicate"},
          {"label":"B","text":"  "},
          {"label":"unknown","text":"not offered"},
          {"label":"B","text":42}, null,
          {"label":"B","text":"Second choice"}
        ]}
        """
        let metadata = try JSONDecoder().decode(MessageMetadata.self, from: Data(json.utf8))
        XCTAssertEqual(metadata.optionDescriptions.count, 2)
        XCTAssertEqual(metadata.optionDescription(for: " A "), "**Plain text**")
        XCTAssertEqual(metadata.optionDescription(for: "B"), "Second choice")
        XCTAssertNil(metadata.optionDescription(for: "C"))
        let encoded = try JSONEncoder().encode(metadata)
        XCTAssertEqual(try JSONDecoder().decode(MessageMetadata.self, from: encoded), metadata)
    }

    func testMissingMalformedAndDescriptionsWithoutOptionsAreIgnored() throws {
        for json in ["{}", "{\"option_descriptions\":42}",
            "{\"option_descriptions\":[{\"label\":\"A\",\"text\":\"Description\"}]}"] {
            let metadata = try JSONDecoder().decode(MessageMetadata.self, from: Data(json.utf8))
            XCTAssertTrue(metadata.optionDescriptions.isEmpty)
        }
    }

    func testTextLimitUsesCharactersAfterTrimming() {
        let metadata = MessageMetadata(options: ["A", "B"], optionDescriptions: [
            OptionDescription(label: "A", text: " " + String(repeating: "🦋", count: 200) + " "),
            OptionDescription(label: "B", text: String(repeating: "a", count: 201))
        ])
        XCTAssertEqual(metadata.optionDescription(for: "A")?.count, 200)
        XCTAssertNil(metadata.optionDescription(for: "B"))
    }
}
