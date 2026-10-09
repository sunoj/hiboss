// Hosted native snapshots of Box rows and explicit empty/error states in light and dark.
// Exports: BoxBrowserSnapshotTests; HIBOSS_SNAPSHOT_DIR writes inspectable PNG artifacts.
// Dependencies: AppKit, SwiftUI, XCTest and synthetic authenticated-media service fixtures.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class BoxBrowserSnapshotTests: XCTestCase {
    func testHostedBoxInLightAndDarkWithLoadedThumbnailAndProvenance() async throws {
        let api = ScriptedBoxBrowser(media: BoxBrowserFixtures.imageData())
        let store = BoxBrowserStore { api }
        let media = BoxBrowserMedia { api }
        defer { media.reset() }
        await store.refresh()
        for scheme in [ColorScheme.light, .dark] {
            let bitmap = try await render(store: store, media: media, scheme: scheme, waitsForImage: true)
            XCTAssertNotNil(media.thumbnails["image"])
            XCTAssertEqual(store.items.filter { $0.provenance != nil }.count, 2)
            try write(bitmap, name: "box-\(scheme == .light ? "light" : "dark")-native")
        }
    }

    func testHostedEmptyAndErrorStates() async throws {
        let api = ScriptedBoxBrowser(pages: [BoxPage(items: [])])
        let store = BoxBrowserStore { api }
        let media = BoxBrowserMedia { api }
        await store.refresh()
        for name in ["empty", "error"] {
            if name == "error" {
                await api.setReadFailure(true)
                await store.refresh()
            }
            for scheme in [ColorScheme.light, .dark] {
                let bitmap = try await render(
                    store: store, media: media, scheme: scheme, waitsForImage: false)
                try write(bitmap, name: "box-\(name)-\(scheme == .light ? "light" : "dark")-native")
            }
        }
    }

    private func render(
        store: BoxBrowserStore, media: BoxBrowserMedia, scheme: ColorScheme, waitsForImage: Bool
    ) async throws -> NSBitmapImageRep {
        _ = NSApplication.shared
        var mounted = false
        let host = NSHostingView(rootView:
            NavigationStack { BoxBrowserView(store: store, media: media) }
                .frame(width: 800, height: 700).environment(\.colorScheme, scheme)
                .onAppear { mounted = true })
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 800, height: 700),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await waitForCondition { mounted && store.didLoad && !store.isLoading }
        if waitsForImage { try await waitForCondition { media.thumbnails["image"] != nil } }
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        XCTAssertGreaterThanOrEqual(bitmap.pixelsWide, 800)
        XCTAssertGreaterThanOrEqual(bitmap.pixelsHigh, 700)
        XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 8, y: 8)).alphaComponent, 1, accuracy: 0.01,
            "The Box background must fill the window in every state")
        return bitmap
    }

    private func write(_ bitmap: NSBitmapImageRep, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["HIBOSS_SNAPSHOT_DIR"] else { return }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url.appendingPathComponent("\(name).png"))
    }
}
