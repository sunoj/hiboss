// Exercises native attachment links in the full-body macOS message surfaces.
// Exports: MessageAttachmentLayoutTests for visible filenames and bounded loaded thumbnails.
// Dependencies: AppKit, SwiftUI, Vision, XCTest, and the loopback snapshot media server.

import AppKit
import HibossKit
import SwiftUI
import Vision
import XCTest
@testable import HibossIsland

@MainActor
final class MessageAttachmentLayoutTests: XCTestCase {
    func testFilenameIsVisibleInEveryFullBodySurface() async throws {
        let message = message(fileURL: "https://example.com/report.pdf")
        let views: [AnyView] = [
            AnyView(HistoryMessageDetail(message: message, reply: AttentionReplyState()) { _ in nil }),
            AnyView(AttentionDetail(item: AttentionItem(message: message), now: .now, onChoose: { _ in })),
            AnyView(OptionMessageBody(text: message.body, attachment: message.metadata?.attachment)
                .background(Color.black))
        ]
        for (index, view) in views.enumerated() {
            let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
            host.sizingOptions = []
            let window = show(host, size: NSSize(width: 360, height: 400))
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(350))
            host.layoutSubtreeIfNeeded()
            let bitmap = try bitmap(host)
            XCTAssertTrue(try recognizedText(bitmap).contains("report.pdf"), "Surface \(index)")
            try write(bitmap, name: "attachment-file-\(index)")
        }
    }

    func testImageThumbnailAndFilenameLinkFitBothAppearances() async throws {
        let media = HistorySnapshotMediaServer()
        defer { media.stop() }
        try await media.start()
        let attachment = try XCTUnwrap(message(fileURL: media.baseURL + "/ship.png").metadata?.attachment)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let host = NSHostingView(rootView: MessageAttachmentView(attachment: attachment).padding()
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, appearance == .aqua ? .light : .dark))
            host.sizingOptions = []
            host.appearance = NSAppearance(named: appearance)
            let window = show(host, size: NSSize(width: 300, height: 240))
            defer { window.close() }
            try await waitForCondition {
                guard let bitmap = try? self.bitmap(host),
                      let color = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?
                        .usingColorSpace(.deviceRGB) else { return false }
                let components = [color.redComponent, color.greenComponent, color.blueComponent]
                return (components.max() ?? 0) - (components.min() ?? 0) > 0.1
            }
            host.layoutSubtreeIfNeeded()
            let bitmap = try bitmap(host)
            XCTAssertTrue(try recognizedText(bitmap).contains("ship.png"))
            XCTAssertLessThanOrEqual(host.fittingSize.width, 300)
            XCTAssertLessThanOrEqual(host.fittingSize.height, 240)
            try write(bitmap, name: "attachment-image-\(appearance.rawValue)")
        }
    }

    private func show(_ host: NSView, size: NSSize) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func bitmap(_ host: NSView) throws -> NSBitmapImageRep {
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    private func recognizedText(_ bitmap: NSBitmapImageRep) throws -> String {
        let request = VNRecognizeTextRequest()
        let image = try XCTUnwrap(bitmap.cgImage)
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }

    private func write(_ bitmap: NSBitmapImageRep, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["HIBOSS_SNAPSHOT_DIR"] else { return }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url.appendingPathComponent("\(name).png"))
    }

    private func message(fileURL: String) -> HistoryMessage {
        HistoryMessage(id: "attachment-layout", body: "Agent result", agentName: "Agent",
            direction: "agent_to_boss", status: "delivered", priority: "normal",
            metadata: MessageMetadata(options: [], fileURL: fileURL), createdAt: "2026-10-09 10:00:00")
    }
}
