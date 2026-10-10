// Hosts the production large viewer and verifies native video playback with a synthetic clip.
// Exports: ProgressMediaViewerTests covering loaded video and explicit invalid-media errors.
// Dependencies: AVKit, AppKit, SwiftUI, XCTest and AVAssetWriter fixture generation.

import AVKit
import AppKit
import HibossKit
import SwiftUI
import Vision
import XCTest
@testable import HibossIsland

@MainActor
final class ProgressMediaViewerTests: XCTestCase {
    func testLargeViewerLoadsVideoIntoNativePlaybackControls() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: file) }
        try await makeVideo(at: file)
        let media = ProgressMedia(url: file.absoluteString, kind: .video, contentType: "video/mp4", size: 0)
        let host = NSHostingView(rootView: ProgressMediaViewer(media: media))
        host.sizingOptions = []
        let window = window(host)
        defer { window.close() }
        try await waitForCondition(timeout: .seconds(10)) {
            self.descendants(host).compactMap { $0 as? AVPlayerView }
                .contains { $0.player?.timeControlStatus == .playing }
        }
        let view = try XCTUnwrap(descendants(host).compactMap { $0 as? AVPlayerView }.first)
        XCTAssertEqual(view.player?.currentItem?.status, .readyToPlay)
        XCTAssertGreaterThan(view.bounds.width, 400)
        XCTAssertGreaterThan(view.bounds.height, 300)
        view.player?.pause()
    }

    func testInvalidVideoShowsAnExplicitUnavailableState() async throws {
        let media = ProgressMedia(url: "http://[", kind: .video, contentType: "video/mp4", size: 0)
        let host = NSHostingView(rootView: ProgressMediaViewer(media: media))
        host.sizingOptions = []
        let window = window(host)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(750))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: try XCTUnwrap(bitmap.cgImage)).perform([request])
        let labels = request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
        XCTAssertTrue(labels.contains { $0.contains(L("Video unavailable")) })
        XCTAssertTrue(labels.contains { $0.contains(L("Retry")) })
        XCTAssertTrue(descendants(host).compactMap { $0 as? AVPlayerView }.isEmpty)
    }

    private func window(_ host: NSView) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 900, height: 650),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        return window
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private func makeVideo(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        let pool = try XCTUnwrap(adaptor.pixelBufferPool)
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer), kCVReturnSuccess)
        let frame = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(frame, [])
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(frame))
        memset(base, 128, CVPixelBufferGetBytesPerRow(frame) * CVPixelBufferGetHeight(frame))
        CVPixelBufferUnlockBaseAddress(frame, [])
        for second in [0, 10] {
            try await waitForCondition { input.isReadyForMoreMediaData }
            XCTAssertTrue(adaptor.append(frame, withPresentationTime: CMTime(seconds: Double(second),
                preferredTimescale: 600)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
    }
}
