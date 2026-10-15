// Measures real option controls against their shared panel height estimate.
// Exports: OptionDescriptionLayoutTests for wrapped copy, media captions, and resolved rows.
// Dependencies: AppKit, SwiftUI, XCTest, and HibossKit.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class OptionDescriptionLayoutTests: XCTestCase {
    func testPlainDescriptionsGrowByTheirRenderedHeight() {
        let options = ["Coast", "Forest", "Mountains"]
        let descriptions = options.map {
            OptionDescription(label: $0, text: String(repeating: "A peaceful place to explore. ", count: 4))
        }
        let plain = message(options: options)
        let described = message(options: options, descriptions: descriptions)
        let delta = OptionPanelLayout.expandedHeight(for: described)
            - OptionPanelLayout.expandedHeight(for: plain)
        let renderedDelta = renderedHeight(options: options, descriptions: descriptions)
            - renderedHeight(options: options)
        XCTAssertGreaterThan(delta, CGFloat(options.count) * OptionRowMetrics.descriptionSpacing)
        XCTAssertEqual(delta, renderedDelta, accuracy: 3)
    }

    func testCaptionedMediaAndWrappedDescriptionsMatchRenderedRows() {
        let options = ["Coast"]
        let media = [OptionMedia(label: "Coast", url: "file:///nonexistent.png", caption: "Coastal view")]
        for descriptions in [[], [OptionDescription(label: "Coast",
            text: String(repeating: "Walk beside the water. ", count: 8))]] {
            let described = message(options: options, descriptions: descriptions, media: media)
            let empty = message(options: [])
            let estimated = OptionPanelLayout.expandedHeight(for: described)
                - OptionPanelLayout.expandedHeight(for: empty)
            XCTAssertEqual(estimated, renderedHeight(options: options, descriptions: descriptions,
                media: media), accuracy: 3)
        }
    }

    func testResolvedRowKeepsDescriptionVisible() {
        let plain = NSHostingView(rootView: ResolvedOptionRow(title: "Coast", chosen: false, source: nil)
            .frame(width: 360).fixedSize(horizontal: false, vertical: true))
        let described = NSHostingView(rootView: ResolvedOptionRow(title: "Coast",
            description: "A quiet break by the water.", chosen: false, source: nil)
            .frame(width: 360).fixedSize(horizontal: false, vertical: true))
        XCTAssertGreaterThan(described.fittingSize.height, plain.fittingSize.height)
    }

    func testOptionButtonDescriptionWrapsWithoutClipping() {
        let plain = NSHostingView(rootView: OptionButton(title: "Coast", action: {})
            .frame(width: 200).fixedSize(horizontal: false, vertical: true))
        let described = NSHostingView(rootView: OptionButton(title: "Coast",
            description: String(repeating: "Walk beside the water. ", count: 8), action: {})
            .frame(width: 200).fixedSize(horizontal: false, vertical: true))
        XCTAssertGreaterThan(described.fittingSize.height, plain.fittingSize.height + 50)
    }

    private func message(options: [String], descriptions: [OptionDescription] = [],
                         media: [OptionMedia] = []) -> OptionMessage {
        OptionMessage(id: "layout", body: "Choose a destination",
            metadata: MessageMetadata(options: options, optionMedia: media, optionDescriptions: descriptions))
    }

    private func renderedHeight(options: [String], descriptions: [OptionDescription] = [],
                                media: [OptionMedia] = []) -> CGFloat {
        let host = NSHostingView(rootView: OptionMediaPicker(options: options, media: media,
            descriptions: descriptions, defaultOption: nil, choose: { _ in })
            .frame(width: AppConstants.Island.width - 36)
            .fixedSize(horizontal: false, vertical: true))
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }
}
