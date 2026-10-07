// Verifies demo comparisons have two distinct, decodable bundled images.
// Exports: DemoOptionMediaTests for offline resources and the optional launch mode.
// Dependencies: XCTest, UIKit, HiBoss DemoOptionMedia.

import UIKit
import XCTest
@testable import HiBoss

final class DemoOptionMediaTests: XCTestCase {
    func testEnabledDemoImagesAreDistinctAndDecodeWithoutNetwork() throws {
        let media = DemoOptionMedia.images(enabled: true)
        XCTAssertEqual(media.map(\.label), ["Coarse grid", "Fine grid"])
        let bytes = try media.map { item in
            let url = try XCTUnwrap(URL(string: item.url))
            XCTAssertTrue(url.isFileURL)
            XCTAssertTrue(url.path.hasPrefix(Bundle.main.bundleURL.path + "/"))
            let data = try Data(contentsOf: url)
            let image = try XCTUnwrap(UIImage(data: data))
            XCTAssertEqual(image.size, CGSize(width: 320, height: 200))
            return data
        }
        XCTAssertEqual(bytes.count, 2)
        XCTAssertNotEqual(bytes.first, bytes.last)
    }

    func testDisabledDemoDoesNotAddOptionMedia() {
        XCTAssertTrue(DemoOptionMedia.images(enabled: false).isEmpty)
    }
}
