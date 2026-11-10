// Covers ImagePipeline caching, request coalescing, outliving cancellation and downsampled decoding.
// The stub protocol counts network requests so a cache hit is proven by the absence of one.
// Dependencies: XCTest, Foundation URLProtocol, CoreGraphics, ImageIO and HibossKit.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import HibossKit

final class ImagePipelineTests: XCTestCase {
    private let url = URL(string: "https://hiboss.example/api/attachments/a.png")!
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("image-pipeline-\(UUID().uuidString)", isDirectory: true)
        ImageStubProtocol.reset(body: Self.png(width: 1000, height: 500))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        ImageStubProtocol.reset(body: Data())
        super.tearDown()
    }

    func testSecondRequestIsServedFromMemoryWithoutANetworkRequest() async throws {
        let pipeline = makePipeline()
        _ = try await pipeline.image(for: url, maxPixelSize: 400)
        let again = try await pipeline.image(for: url, maxPixelSize: 400)
        XCTAssertEqual(again.cgImage.width, 400)
        XCTAssertEqual(ImageStubProtocol.requests, 1)
        XCTAssertNotNil(pipeline.cachedImage(for: url, maxPixelSize: 400))
    }

    func testDiskCacheServesANewPipelineWithoutANetworkRequest() async throws {
        _ = try await makePipeline().image(for: url, maxPixelSize: 400)
        try await waitForDiskEntry()
        let relaunched = makePipeline()
        XCTAssertNil(relaunched.cachedImage(for: url, maxPixelSize: 400))
        let image = try await relaunched.image(for: url, maxPixelSize: 800)
        XCTAssertEqual(image.cgImage.width, 800)
        XCTAssertEqual(ImageStubProtocol.requests, 1)
    }

    func testConcurrentRequestsForOneURLShareOneDownload() async throws {
        ImageStubProtocol.delay = 0.3
        let pipeline = makePipeline(), url = url
        let widths = try await withThrowingTaskGroup(of: Int.self) { group in
            for size in [100, 200, 300, 400, 500] {
                group.addTask { try await pipeline.image(for: url, maxPixelSize: size).cgImage.width }
            }
            return try await group.reduce(into: Set<Int>()) { $0.insert($1) }
        }
        XCTAssertEqual(widths, [100, 200, 300, 400, 500])
        XCTAssertEqual(ImageStubProtocol.requests, 1)
    }

    func testCancelledRequestLeavesTheDownloadRunningForTheNextRequest() async throws {
        ImageStubProtocol.delay = 0.3
        let pipeline = makePipeline(), url = url
        let first = Task { try await pipeline.image(for: url, maxPixelSize: 200) }
        try await Task.sleep(for: .milliseconds(50))
        first.cancel()
        let image = try await pipeline.image(for: url, maxPixelSize: 300)
        XCTAssertEqual(image.cgImage.width, 300)
        XCTAssertEqual(ImageStubProtocol.requests, 1)
    }

    func testFailedResponseIsNotCachedAndRetrySucceeds() async throws {
        ImageStubProtocol.status = 500
        let pipeline = makePipeline()
        do {
            _ = try await pipeline.image(for: url, maxPixelSize: 200)
            XCTFail("Expected a failure")
        } catch {}
        ImageStubProtocol.status = 200
        _ = try await pipeline.image(for: url, maxPixelSize: 200, reload: true)
        XCTAssertEqual(ImageStubProtocol.requests, 2)
    }

    func testDownsamplingKeepsTheOriginalPointSize() throws {
        let decoded = try ImageDownsampler.decode(Self.png(width: 1000, height: 500), maxPixelSize: 250)
        XCTAssertEqual(decoded.cgImage.width, 250)
        XCTAssertEqual(decoded.cgImage.height, 125)
        XCTAssertEqual(decoded.originalPixelSize, CGSize(width: 1000, height: 500))
        XCTAssertEqual(decoded.scale, 0.25, accuracy: 0.001)
        let small = try ImageDownsampler.decode(Self.png(width: 100, height: 50), maxPixelSize: 400)
        XCTAssertEqual(small.cgImage.width, 100)
    }

    private func makePipeline() -> ImagePipeline {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ImageStubProtocol.self]
        return ImagePipeline(session: URLSession(configuration: config),
                             disk: BoxThumbnailCache(directory: directory, capacity: 50 * 1024 * 1024))
    }

    private func waitForDiskEntry() async throws {
        for _ in 0..<100 {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            if !files.isEmpty { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("The download was never written to the disk cache")
    }

    static func png(width: Int, height: Int) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}

final class ImageStubProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var state = (requests: 0, body: Data(), status: 200, delay: 0.0)

    static var requests: Int { lock.withLock { state.requests } }
    static var status: Int {
        get { lock.withLock { state.status } }
        set { lock.withLock { state.status = newValue } }
    }
    static var delay: TimeInterval {
        get { lock.withLock { state.delay } }
        set { lock.withLock { state.delay = newValue } }
    }

    static func reset(body: Data) { lock.withLock { state = (0, body, 200, 0) } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let current = Self.lock.withLock { () -> (Data, Int, TimeInterval) in
            Self.state.requests += 1
            return (Self.state.body, Self.state.status, Self.state.delay)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + current.2) { [self] in
            let response = HTTPURLResponse(url: request.url!, statusCode: current.1, httpVersion: nil,
                                           headerFields: ["Cache-Control": "public, max-age=31536000, immutable"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: current.0)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
