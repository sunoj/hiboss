// Clicks the production Box image entry point in a hosted native browser.
// Verifies compact/wide previews, dismissal and repeat opening without another download.
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
        store.selection = "image"
        let window = show(store: store, media: media, width: 800, appearance: .aqua)
        defer { window.close() }
        try await waitForCondition { media.errors["image"] != nil }
        let detail = try await detailWindow(in: window)
        try clickLabel(L("Open"), in: XCTUnwrap(detail.contentView), window: detail)
        try await waitForCondition { detail.attachedSheet != nil }
        let sheet = try XCTUnwrap(detail.attachedSheet)
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

    func testSelectedImageOpensFullResolutionImageInBothAppearances() async throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for width in [CGFloat(480), 800, 960] {
                try await verifySelectedImage(width: width, appearance: appearance)
            }
        }
    }

    private func verifySelectedImage(width: CGFloat, appearance: NSAppearance.Name) async throws {
        let api = ScriptedBoxBrowser(media: try imageData())
        let store = BoxBrowserStore { api }
        let media = BoxBrowserMedia { api }
        defer { media.reset() }
        await store.refresh()
        let window = show(store: store, media: media, width: width, appearance: appearance)
        defer { window.close() }
        try await waitForCondition { media.thumbnails["image"] != nil }
        store.selection = "image"
        let detail = try await detailWindow(in: window)
        let detailContent = try XCTUnwrap(detail.contentView)
        try await waitForCondition {
            (try? self.recognize(detailContent).contains { $0.text == L("Open") }) == true
        }
        try clickLabel(L("Open"), in: detailContent, window: detail)
        try await waitForCondition { detail.attachedSheet != nil }
        let sheet = try XCTUnwrap(detail.attachedSheet)
        try await waitForCondition { self.imageView(sheet.contentView)?.image != nil }
        let image = try XCTUnwrap(imageView(sheet.contentView))
        XCTAssertEqual(image.image?.size, NSSize(width: 1800, height: 1200))
        XCTAssertGreaterThan(image.bounds.width, 400)
        XCTAssertGreaterThan(image.bounds.height, 300)
        XCTAssertLessThanOrEqual(image.bounds.width, sheet.contentView?.bounds.width ?? 0)
        XCTAssertEqual(image.bounds.width / image.bounds.height, 1.5, accuracy: 0.01)
        try capture(sheet, name: "box-image-\(Int(width))-\(appearance.rawValue)")
        try clickLabel(L("Close"), in: XCTUnwrap(sheet.contentView), window: sheet)
        try await waitForCondition { detail.attachedSheet == nil }
        XCTAssertEqual(store.selection, "image", "Closing the viewer retains the selected detail")
        try clickLabel(L("Open"), in: detailContent, window: detail)
        try await waitForCondition { detail.attachedSheet != nil }
        let downloads = await api.downloadsByID["image"]
        XCTAssertEqual(downloads, 1)
    }

    private func show(store: BoxBrowserStore, media: BoxBrowserMedia,
                      width: CGFloat, appearance: NSAppearance.Name) -> NSWindow {
        let host = NSHostingView(rootView: NavigationStack { BoxBrowserView(store: store, media: media) })
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 60, y: 60, width: width, height: 700),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func detailWindow(in window: NSWindow) async throws -> NSWindow {
        if window.contentLayoutRect.width >= 900 { return window }
        try await waitForCondition { window.attachedSheet != nil }
        return try XCTUnwrap(window.attachedSheet)
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
        try BoxWindowCaptureSupport.capture(window, directory: directory, name: name + "-window")
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
