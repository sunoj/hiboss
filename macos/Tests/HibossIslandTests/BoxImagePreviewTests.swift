// Clicks the production Box image entry point in a hosted native browser.
// Verifies full-resolution preview, dismissal and repeat opening without another download.
// Dependencies: AppKit, SwiftUI, XCTest and synthetic authenticated Box media.

import AppKit
import HibossKit
import SwiftUI
import Vision
import XCTest
@testable import HibossIsland

@MainActor
final class BoxImagePreviewTests: XCTestCase {
    func testFailedImageCanRetryInTheLargeViewer() async throws {
        let provider = BoxPreviewAPIProvider(ScriptedBoxBrowser(media: Data("invalid image".utf8)))
        let store = BoxBrowserStore { provider.api }
        let media = BoxBrowserMedia { provider.api }
        defer { media.reset() }
        await store.refresh()
        let host = NSHostingView(rootView: NavigationStack { BoxBrowserView(store: store, media: media) })
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 60, y: 60, width: 800, height: 700),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await waitForCondition { media.errors["image"] != nil }
        try clickLabel(L("Open"), in: host, window: window)
        try await waitForCondition { window.attachedSheet != nil }
        let sheet = try XCTUnwrap(window.attachedSheet)
        let content = try XCTUnwrap(sheet.contentView)
        try await waitForCondition {
            (try? self.recognize(content).contains { $0.text.contains(L("Image unavailable")) }) == true
        }
        try capture(sheet, name: "box-image-error")
        provider.api = ScriptedBoxBrowser(media: try imageData())
        try clickLabel(L("Retry image"), in: content, window: sheet)
        try await waitForCondition { self.imageView(content)?.image != nil }
        XCTAssertEqual(imageView(content)?.image?.size, NSSize(width: 1800, height: 1200))
        try capture(sheet, name: "box-image-retried")
        let downloads = await provider.api.downloads
        XCTAssertEqual(downloads, 1)
    }

    func testThumbnailOpensFullResolutionImageInBothAppearances() async throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let api = ScriptedBoxBrowser(media: try imageData())
            let store = BoxBrowserStore { api }
            let media = BoxBrowserMedia { api }
            defer { media.reset() }
            await store.refresh()
            let host = NSHostingView(rootView: NavigationStack { BoxBrowserView(store: store, media: media) })
            host.sizingOptions = []
            let window = NSWindow(contentRect: NSRect(x: 60, y: 60, width: 800, height: 700),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: appearance)
            window.contentView = host
            window.orderFront(nil)
            defer { window.close() }
            try await waitForCondition { media.thumbnails["image"] != nil }
            let filename = try XCTUnwrap(recognize(host).first { $0.text == "Navigation preview.png" })
            let thumbnail = CGPoint(x: 64 / host.bounds.width, y: filename.bounds.midY)
            try click(thumbnail, in: host, window: window)
            try await waitForCondition { window.attachedSheet != nil }
            let sheet = try XCTUnwrap(window.attachedSheet)
            try await waitForCondition { self.imageView(sheet.contentView)?.image != nil }
            let image = try XCTUnwrap(imageView(sheet.contentView))
            XCTAssertEqual(image.image?.size, NSSize(width: 1800, height: 1200))
            XCTAssertGreaterThan(image.bounds.width, 400)
            XCTAssertGreaterThan(image.bounds.height, 300)
            XCTAssertLessThanOrEqual(image.bounds.width, sheet.contentView?.bounds.width ?? 0)
            XCTAssertEqual(image.bounds.width / image.bounds.height, 1.5, accuracy: 0.01)
            try capture(sheet, name: "box-image-\(appearance.rawValue)")
            try clickLabel(L("Close"), in: XCTUnwrap(sheet.contentView), window: sheet)
            try await waitForCondition { window.attachedSheet == nil }
            try clickLabel(L("Open"), in: host, window: window)
            try await waitForCondition { window.attachedSheet != nil }
            let downloads = await api.downloads
            XCTAssertEqual(downloads, 1)
        }
    }

    private func clickLabel(_ label: String, in host: NSView, window: NSWindow) throws {
        let text = try XCTUnwrap(recognize(host).filter { $0.text == label }
            .max { $0.bounds.midY < $1.bounds.midY })
        try click(CGPoint(x: text.bounds.midX, y: text.bounds.midY), in: host, window: window)
    }

    private func click(_ normalized: CGPoint, in host: NSView, window: NSWindow) throws {
        let point = host.convert(NSPoint(x: normalized.x * host.bounds.width,
            y: (host.isFlipped ? 1 - normalized.y : normalized.y) * host.bounds.height), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            window.sendEvent(event)
        }
    }

    private func recognize(_ host: NSView) throws -> [(text: String, bounds: CGRect)] {
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
        return (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map { ($0.string, observation.boundingBox) }
        }
    }

    private func imageView(_ root: NSView?) -> NSImageView? {
        guard let root else { return nil }
        if let image = root as? NSImageView, image.identifier?.rawValue == "box.preview.image" {
            return image
        }
        return root.subviews.compactMap { imageView($0) }.first
    }

    private func imageData() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1800, height: 1200,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0, green: 0.45, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 1800, height: 1200))
        context.setFillColor(red: 1, green: 0.8, blue: 0, alpha: 1)
        context.fill(CGRect(x: 200, y: 200, width: 1400, height: 200))
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    private func capture(_ window: NSWindow, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["HIBOSS_SNAPSHOT_DIR"] else { return }
        let host = try XCTUnwrap(window.contentView)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
    }
}

@MainActor
private final class BoxPreviewAPIProvider {
    var api: ScriptedBoxBrowser
    init(_ api: ScriptedBoxBrowser) { self.api = api }
}
