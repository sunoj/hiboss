// Exercises public image loading and placeholder fallback across missing/failing URLs.
// Covers: cache reuse, failures, URL validation, credential isolation, and square clipping.
// Dependencies: XCTest, AppKit, SwiftUI, HibossKit, and loopback media fixture server.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class ProjectAvatarTests: XCTestCase {
    func testSuccessfulAvatarIsReusedWithoutAnotherRequest() async throws {
        let server = HistorySnapshotMediaServer()
        try await server.start()
        defer { server.stop() }
        let path = "/ship.png?avatar=\(UUID().uuidString)"
        let url = try XCTUnwrap(URL(string: server.baseURL + path))
        let original = ProjectAvatarLoader()
        await original.load(url)
        let image = try XCTUnwrap(original.image)
        XCTAssertEqual(server.requestedPaths, [path])

        let rebuilt = ProjectAvatarLoader(url: url)
        XCTAssertTrue(rebuilt.image === image, "A rebuilt loader must have its image before loading")
        XCTAssertEqual(server.requestedPaths, [path], "Initialization must not make a request")
        XCTAssertNil(ProjectAvatarLoader().image)
        let coldURL = try XCTUnwrap(URL(string: server.baseURL + "/ship.png?avatar=\(UUID().uuidString)"))
        XCTAssertNil(ProjectAvatarLoader(url: coldURL).image, "The cache key must include the whole URL")
        await rebuilt.load(url)
        XCTAssertTrue(rebuilt.image === image)
        XCTAssertEqual(server.requestedPaths, [path], "A cached avatar must make zero new requests")
        await rebuilt.load(nil)
        XCTAssertNil(rebuilt.image, "A changed project must never retain the previous image")
        await rebuilt.load(url)
        XCTAssertTrue(rebuilt.image === image)
        XCTAssertEqual(server.requestedPaths, [path])
    }

    func testHTTPFailuresAndInvalidImagesAreNotCachedAndAreRetried() async throws {
        let server = HistorySnapshotMediaServer()
        try await server.start()
        defer { server.stop() }
        for resource in ["missing.png", "port"] {
            let path = "/\(resource)?avatar=\(UUID().uuidString)"
            let url = try XCTUnwrap(URL(string: server.baseURL + path))
            let loader = ProjectAvatarLoader(url: url)
            await loader.load(url)
            XCTAssertNil(loader.image)
            let rebuilt = ProjectAvatarLoader(url: url)
            XCTAssertNil(rebuilt.image, "Only successfully decoded 2xx images may be cached")
            await rebuilt.load(url)
            XCTAssertNil(rebuilt.image)
            XCTAssertEqual(server.requestedPaths.filter { $0 == path }.count, 2)
        }
    }

    func testNonSuccessResponseWithValidImageIsNotCached() async throws {
        let configuration = ProjectAvatarLoader.configuration()
        configuration.protocolClasses = [AvatarRequestProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let url = try XCTUnwrap(URL(string: "https://avatars.example.com/image.png?avatar=\(UUID().uuidString)"))
        let loader = ProjectAvatarLoader(url: url)
        await loader.load(url, session: session)
        XCTAssertNil(loader.image)
        XCTAssertNil(ProjectAvatarLoader(url: url).image)
    }

    func testTransportFailureIsNotCached() async throws {
        let configuration = ProjectAvatarLoader.configuration()
        configuration.protocolClasses = [AvatarRequestProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let url = try XCTUnwrap(URL(string: "https://avatars.example.com/failure?avatar=\(UUID().uuidString)"))
        let loader = ProjectAvatarLoader(url: url)
        await loader.load(url, session: session)
        XCTAssertNil(loader.image)
        XCTAssertNil(ProjectAvatarLoader(url: url).image)
    }

    func testInvalidURLsNeverSeedOrRetainAnImage() async throws {
        let server = HistorySnapshotMediaServer()
        try await server.start()
        defer { server.stop() }
        let path = "/ship.png?avatar=\(UUID().uuidString)"
        let url = try XCTUnwrap(URL(string: server.baseURL + path))
        let loader = ProjectAvatarLoader()
        await loader.load(url)
        XCTAssertNotNil(loader.image)
        for invalid in ["file:///tmp/avatar.png", "ftp://example.com/avatar.png", "https:avatar.png",
                        "http://user@127.0.0.1/avatar.png", "https://user:password@example.com/avatar.png"] {
            let invalidURL = try XCTUnwrap(URL(string: invalid))
            XCTAssertNil(ProjectAvatarLoader(url: invalidURL).image)
            await loader.load(invalidURL)
            XCTAssertNil(loader.image)
        }
        XCTAssertEqual(server.requestedPaths, [path])
    }

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

    func testWhiteInitialsHaveReadableTintContrast() throws {
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

    func testPlaceholderAndUploadedImageUseTheSameContinuousSquareAtEverySize() throws {
        let image = NSImage(size: NSSize(width: 80, height: 40), flipped: false) { rect in
            NSColor.black.setFill()
            rect.fill()
            return true
        }
        for size: CGFloat in [20, 44, 80] {
            let expected = try alphaMask(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(.black).frame(width: size, height: size))
            for slug in ["hiboss", "house", "smart-router", "ai-dispatch"] {
                for avatar in [nil, image] {
                    let content = ProjectAvatarContent(placeholder: ProjectAvatarPlaceholder(slug: slug),
                        image: avatar, size: size)
                    let actual = try alphaMask(content)
                    XCTAssertEqual(actual.count, expected.count)
                    XCTAssertEqual(zip(actual, expected).filter { abs($0 - $1) > 2 / 255 + 0.0001 }.count,
                                   0, "\(slug), \(size)")
                }
            }
        }
    }

    func testAgentInitialsAreCircular() throws {
        let expected = try alphaMask(Circle().fill(Color.primary.opacity(0.05))
            .frame(width: 20, height: 20))
        let agent = try alphaMask(AgentAvatarView(name: "Build Agent", size: 20))
        XCTAssertEqual(Array(agent.prefix(80)), Array(expected.prefix(80)))
    }

    private func alphaMask<Content: View>(_ content: Content) throws -> [CGFloat] {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(renderer.nsImage?.tiffRepresentation)))
        return (0..<bitmap.pixelsHigh).flatMap { y in
            (0..<bitmap.pixelsWide).map { x in bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0 }
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
        if request.url?.lastPathComponent == "failure" {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)
        else {
            XCTFail("The avatar request must have an HTTP URL")
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        guard let png = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII="),
              NSImage(data: png) != nil else {
            XCTFail("The non-2xx fixture must contain a decodable image")
            return
        }
        client?.urlProtocol(self, didLoad: png)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
