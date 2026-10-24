// Covers the shared Box thumbnail generator: 512 px bound, EXIF orientation, poster frames,
// flattening onto white and the 256 KiB quality fallback. Fixtures are synthesized in a temporary directory.
// Dependencies: XCTest, AVFoundation, ImageIO and HibossKit.

@preconcurrency import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import HibossKit

final class BoxThumbnailGeneratorTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testLongestSideIsBoundedTo512AndOutputIsJPEG() async throws {
        let url = try writeJPEG(width: 2000, height: 1000)
        let data = try await XCTUnwrapAsync(await BoxThumbnailGenerator.thumbnail(for: url, kind: .image))
        XCTAssertTrue(data.starts(with: [0xFF, 0xD8, 0xFF]))
        XCTAssertLessThanOrEqual(data.count, BoxThumbnailGenerator.maxBytes)
        XCTAssertEqual(try size(of: data), CGSize(width: 512, height: 256))
    }

    func testExifOrientationIsApplied() async throws {
        let url = try writeJPEG(width: 1000, height: 500, orientation: .right)
        let data = try await XCTUnwrapAsync(await BoxThumbnailGenerator.thumbnail(for: url, kind: .image))
        XCTAssertEqual(try size(of: data), CGSize(width: 256, height: 512))
    }

    func testSmallImageIsNotUpscaledAndOtherKindsHaveNone() async throws {
        let url = try writeJPEG(width: 120, height: 80)
        let data = try await XCTUnwrapAsync(await BoxThumbnailGenerator.thumbnail(for: url, kind: .image))
        XCTAssertEqual(try size(of: data), CGSize(width: 120, height: 80))
        let none = await BoxThumbnailGenerator.thumbnail(for: url, kind: .file)
        XCTAssertNil(none)
    }

    func testOversizedOutputRetriesAtHalfQualityThenIsDropped() throws {
        let image = try noise(width: 512, height: 512)
        let high = try XCTUnwrap(BoxThumbnailGenerator.encode(image, quality: 0.7))
        let low = try XCTUnwrap(BoxThumbnailGenerator.encode(image, quality: 0.5))
        XCTAssertLessThan(low.count, high.count)
        XCTAssertEqual(BoxThumbnailGenerator.jpeg(image, limit: high.count), high)
        XCTAssertEqual(BoxThumbnailGenerator.jpeg(image, limit: high.count - 1), low)
        XCTAssertNil(BoxThumbnailGenerator.jpeg(image, limit: low.count - 1))
    }

    func testVideoPosterIsBoundedTo512() async throws {
        let url = directory.appendingPathComponent("clip.mp4")
        try await BoxThumbnailVideoFixture.write(to: url, width: 1280, height: 720)
        let data = try await XCTUnwrapAsync(await BoxThumbnailGenerator.thumbnail(for: url, kind: .video))
        XCTAssertTrue(data.starts(with: [0xFF, 0xD8, 0xFF]))
        XCTAssertEqual(try size(of: data), CGSize(width: 512, height: 288))
    }

    func testTranslucentImageIsFlattenedOntoWhite() async throws {
        let url = directory.appendingPathComponent("clear.png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try transparent(width: 64, height: 64), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let data = try await XCTUnwrapAsync(await BoxThumbnailGenerator.thumbnail(for: url, kind: .image))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertGreaterThan(pixel[0], 240, "half-transparent red over white stays light red")
        XCTAssertTrue((100...170).contains(pixel[1]) && (100...170).contains(pixel[2]), "\(pixel)")
    }

    private func XCTUnwrapAsync<T>(_ value: T?) async throws -> T { try XCTUnwrap(value) }

    private func size(of data: Data) throws -> CGSize {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return CGSize(width: image.width, height: image.height)
    }

    private func writeJPEG(
        width: Int, height: Int, orientation: CGImagePropertyOrientation = .up
    ) throws -> URL {
        let url = directory.appendingPathComponent(UUID().uuidString + ".jpg")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        let properties = [kCGImagePropertyOrientation: orientation.rawValue] as CFDictionary
        CGImageDestinationAddImage(destination, try noise(width: width, height: height), properties)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func transparent(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 0.5))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func noise(width: Int, height: Int) throws -> CGImage {
        var generator = SystemRandomNumberGenerator()
        var pixels = (0..<(width * height * 4)).map { _ in UInt8.random(in: 0...255, using: &generator) }
        let context = try XCTUnwrap(CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        return try XCTUnwrap(context.makeImage())
    }
}

/// Writes a short H.264 clip of solid frames for poster-frame tests.
enum BoxThumbnailVideoFixture {
    static func write(to url: URL, width: Int, height: Int) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<10 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 5_000_000) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
            guard let buffer else { throw CocoaError(.fileWriteUnknown) }
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer), 0x80, CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }
}
