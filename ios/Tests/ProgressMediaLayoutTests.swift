// Layout math for Twitter-style progress media groups.
// Exports: ProgressMediaLayoutTests.
// Dependencies: XCTest, HiBoss app target.

import HibossKit
import SwiftUI
import UIKit
import XCTest
@testable import HiBoss

final class ProgressMediaLayoutTests: XCTestCase {
    func testMissingDimensionsUseSixteenNine() {
        XCTAssertEqual(
            ProgressMediaLayout.clampedAspect(width: nil, height: nil),
            16 / 9,
            accuracy: 0.0001
        )
    }

    func testPortraitIsClampedToThreeFour() {
        XCTAssertEqual(
            ProgressMediaLayout.clampedAspect(width: 100, height: 200),
            3 / 4,
            accuracy: 0.0001
        )
    }

    func testLandscapeIsClampedToTwoOne() {
        XCTAssertEqual(
            ProgressMediaLayout.clampedAspect(width: 300, height: 100),
            2,
            accuracy: 0.0001
        )
    }

    func testUnclampedRatiosPassThrough() {
        XCTAssertEqual(
            ProgressMediaLayout.clampedAspect(width: 16, height: 9),
            16 / 9,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            ProgressMediaLayout.clampedAspect(width: 3, height: 4),
            3 / 4,
            accuracy: 0.0001
        )
    }

    @MainActor
    func testMeasuredRatioCannotResizeAReservedUndimensionedImage() async throws {
        URLProtocol.registerClass(PortraitImageProtocol.self)
        defer { URLProtocol.unregisterClass(PortraitImageProtocol.self) }
        for (index, dimensioned) in [false, true].enumerated() {
            let media = ProgressMedia(url: "https://stability.invalid/portrait.png", kind: .image,
                                      contentType: "image/png", size: 100,
                                      width: dimensioned ? 16 : nil, height: dimensioned ? 9 : nil)
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let scene = try XCTUnwrap(scenes.first)
            let host = UIHostingController(rootView: ProgressMediaView(items: [media], onOpen: { _ in }))
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            window.rootViewController = host
            window.isHidden = false
            defer { window.isHidden = true }
            let before = host.sizeThatFits(in: CGSize(width: 390, height: 2_000))
            let loaded = expectation(description: "portrait image completion")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { loaded.fulfill() }
            await fulfillment(of: [loaded], timeout: 2)
            let after = host.sizeThatFits(in: CGSize(width: 390, height: 2_000))
            XCTAssertEqual(PortraitImageProtocol.deliveries.count, index + 1,
                           "The media completion path must run")
            XCTAssertEqual(after.height, before.height, accuracy: 1)
        }
    }

    func testServerDimensionsDetermineReservedAspect() {
        XCTAssertEqual(
            ProgressMediaLayout.clampedAspect(width: 16, height: 9),
            16 / 9,
            accuracy: 0.0001
        )
    }

    func testDurationLabelFormatsMinutesAndSeconds() {
        let en = Locale(identifier: "en_US")
        XCTAssertEqual(ProgressMediaLayout.durationLabel(milliseconds: 0, locale: en), "0:00")
        XCTAssertEqual(ProgressMediaLayout.durationLabel(milliseconds: 15_000, locale: en), "0:15")
        XCTAssertEqual(ProgressMediaLayout.durationLabel(milliseconds: 65_000, locale: en), "1:05")
    }
}

private final class PortraitImageProtocol: URLProtocol, @unchecked Sendable {
    static let deliveries = ImageDeliveries()
    private static let png = Data([
        137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82,
        0, 0, 0, 2, 0, 0, 0, 4, 8, 6, 0, 0, 0, 164, 239, 238,
        57, 0, 0, 0, 16, 73, 68, 65, 84, 120, 156, 99, 96, 96, 96, 248,
        15, 197, 184, 24, 0, 131, 160, 7, 249, 208, 82, 25, 172, 0, 0, 0,
        0, 73, 69, 78, 68, 174, 66, 96, 130,
    ])

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "stability.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { [self] in
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                 headerFields: ["Content-Type": "image/png"]) else { return }
            Self.deliveries.record()
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.png)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

private final class ImageDeliveries: @unchecked Sendable {
    private let lock = NSLock()
    private var delivered = 0
    var count: Int { lock.withLock { delivered } }
    func record() { lock.withLock { delivered += 1 } }
}
