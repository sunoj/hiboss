// Exercises public image loading and placeholder fallback across missing/failing URLs.
// Covers: loading state, HTTP errors, malformed images, valid images, no credentials, and shapes.
// Dependencies: XCTest, AppKit, SwiftUI, HibossKit, and loopback media fixture server.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class ProjectAvatarTests: XCTestCase {
    func testLoadingMissingFailureAndInvalidImagesKeepPlaceholderThenSuccessLoadsImage() async throws {
        let server = HistorySnapshotMediaServer()
        try await server.start()
        defer { server.stop() }
        let loader = ProjectAvatarLoader()
        XCTAssertNil(loader.image, "Loading must show the placeholder")
        for url in [nil, URL(string: server.baseURL + "/missing.png"),
                    URL(string: server.baseURL + "/port"), URL(string: "file:///tmp/avatar.png"),
                    URL(string: "https://user:password@example.com/avatar.png")] {
            await loader.load(url)
            XCTAssertNil(loader.image, "Missing and failed avatars must show the placeholder")
        }
        await loader.load(URL(string: server.baseURL + "/ship.png"))
        XCTAssertNotNil(loader.image)
        await loader.load(nil)
        XCTAssertNil(loader.image, "A changed project must never retain the previous image")
    }

    func testAvatarSessionDoesNotShareCredentialsCookiesOrAuthorizationHeaders() {
        let configuration = ProjectAvatarLoader.configuration()
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertTrue(configuration.httpAdditionalHeaders?.isEmpty == true)
    }

    func testPublicAvatarRequestSendsNoAuthorizationOrCookie() async throws {
        let configuration = ProjectAvatarLoader.configuration()
        configuration.protocolClasses = [AvatarRequestProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let loader = ProjectAvatarLoader()
        let url = try XCTUnwrap(URL(string: "https://avatars.example.com/image.png"))
        await loader.load(url, session: session)
        XCTAssertNil(loader.image)
    }

    func testAllPlaceholderShapesHaveStableBoundsAndWhiteInitialsHaveReadableTintContrast() throws {
        for shape in ProjectAvatarPlaceholder.Shape.allCases {
            let bounds = ProjectAvatarShape(kind: shape).path(in: CGRect(x: 0, y: 0, width: 40, height: 40))
                .boundingRect
            XCTAssertEqual(bounds, CGRect(x: 0, y: 0, width: 40, height: 40))
        }
        for scheme in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: scheme))
            for tint in ProjectAvatarPlaceholder.Tint.allCases {
                let color = try XCTUnwrap(NSColor(named: tint.assetName, bundle: appResourceBundle))
                var resolved: NSColor?
                appearance.performAsCurrentDrawingAppearance { resolved = color.usingColorSpace(.sRGB) }
                let rgb = try XCTUnwrap(resolved)
                let luminance = linear(rgb.redComponent) * 0.2126 + linear(rgb.greenComponent) * 0.7152
                    + linear(rgb.blueComponent) * 0.0722
                XCTAssertGreaterThanOrEqual(1.05 / (luminance + 0.05), 4.5, tint.assetName)
            }
        }
    }

    private func linear(_ value: CGFloat) -> CGFloat {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
}

private final class AvatarRequestProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)
        else {
            XCTFail("The avatar request must have an HTTP URL")
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
