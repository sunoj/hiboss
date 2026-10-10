// Resolves settled option images from the original decision metadata.
// Exports: HistoryChosenOptionImageTests for exact labels, whitespace and non-choice outcomes.
// Dependencies: XCTest, HibossKit and HistoryOptionSelection.

import HibossKit
import XCTest
@testable import HibossIsland

final class HistoryChosenOptionImageTests: XCTestCase {
    func testChosenImageResolvesFromDecodedMetadataRatherThanMediaOrder() throws {
        let json = """
        {"options":["Hold"," Ship "],"option_media":[
          {"label":"Hold","url":"https://example.invalid/hold.png"},
          {"label":"Ship","url":"https://example.invalid/ship.png","caption":"Release preview"}
        ]}
        """
        let metadata = try JSONDecoder().decode(MessageMetadata.self, from: Data(json.utf8))
        let selected = HistoryOptionSelection.selectedMedia(in: metadata,
            outcome: .chosen(option: " Ship\n", source: "ios"))
        XCTAssertEqual(selected, metadata.optionMedia[1])
    }

    func testAutomaticSelectionResolvesItsImage() {
        XCTAssertEqual(HistoryOptionSelection.selectedMedia(in: metadata,
            outcome: .autoSelected(option: " Hold ")), metadata.optionMedia.first)
    }

    func testNonChoiceOutcomesDoNotResolveAnImage() {
        for outcome in [ThreadOutcome.open, .none, .expired, .autoSelected(option: nil),
                        .replied(text: "Hold", source: "ios")] {
            XCTAssertNil(HistoryOptionSelection.selectedMedia(in: metadata, outcome: outcome))
        }
    }

    func testMissingImageAndDifferentCaseDoNotFallBackToAnotherOption() {
        for answer in ["Ship", "hold", "Custom answer"] {
            XCTAssertNil(HistoryOptionSelection.selectedMedia(in: metadata,
                outcome: .chosen(option: answer, source: nil)))
        }
        XCTAssertNil(HistoryOptionSelection.selectedMedia(in: nil,
            outcome: .chosen(option: "Hold", source: nil)))
    }

    @MainActor
    func testImageLoaderBoundsThumbnailsAndKeepsFullResolutionForViewing() async throws {
        let server = HistorySnapshotMediaServer()
        defer { server.stop() }
        try await server.start()
        let url = try XCTUnwrap(URL(string: "\(server.baseURL)/ship.png"))
        let thumbnail = try await OptionMediaImage.loadImage(from: url, maxPixelSize: 264)
        let fullSize = try await OptionMediaImage.loadImage(from: url)
        XCTAssertEqual(max(thumbnail.width, thumbnail.height), 264)
        XCTAssertGreaterThan(fullSize.width, thumbnail.width)
        XCTAssertGreaterThan(fullSize.height, thumbnail.height)
    }

    @MainActor
    func testImageLoaderRejectsAnUnavailableAttachment() async throws {
        let server = HistorySnapshotMediaServer()
        defer { server.stop() }
        try await server.start()
        let url = try XCTUnwrap(URL(string: "\(server.baseURL)/missing.png"))
        do {
            _ = try await OptionMediaImage.loadImage(from: url)
            XCTFail("An unavailable attachment must not produce an image")
        } catch HibossAPIError.invalidResponse {
            // The HTTP error is rejected before attempting image decoding.
        } catch {
            XCTFail("Unexpected attachment error: \(error)")
        }
    }

    private var metadata: MessageMetadata {
        MessageMetadata(options: ["Hold", "Ship"], optionMedia: [
            OptionMedia(label: "Hold", url: "https://example.invalid/hold.png")
        ])
    }
}
