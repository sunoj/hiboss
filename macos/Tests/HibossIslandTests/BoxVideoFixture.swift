// Generates a small synthetic video so window tests exercise decoded video frame thumbnails.
// Exports: BoxVideoFixture.data; temporary output is removed after reading.
// Dependencies: AVFoundation, CoreVideo and XCTest.

import AVFoundation
import CoreVideo
import XCTest

enum BoxVideoFixture {
    static func data() async throws -> Data {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB
            ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var pixelBuffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32ARGB,
            nil, &pixelBuffer), kCVReturnSuccess)
        let buffer = try XCTUnwrap(pixelBuffer)
        CVPixelBufferLockBaseAddress(buffer, [])
        let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        for offset in stride(from: 0, to: CVPixelBufferGetDataSize(buffer), by: 4) {
            bytes[offset] = 255
            bytes[offset + 1] = 40
            bytes[offset + 2] = 120
            bytes[offset + 3] = 180
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !input.isReadyForMoreMediaData && ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertTrue(adaptor.append(buffer, withPresentationTime: .zero))
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(seconds: 12, preferredTimescale: 600))
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        return try Data(contentsOf: url)
    }
}
