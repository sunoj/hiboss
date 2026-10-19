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
    func testPersistentDetailWithAndWithoutSelectionInBothAppearances() async throws {
        let api = ScriptedBoxBrowser(media: BoxBrowserFixtures.imageData())
        let store = BoxBrowserStore { api }
        let media = BoxBrowserMedia { api }
        defer { media.reset() }
        await store.refresh()
        XCTAssertEqual(store.collections.count, 2)
        XCTAssertTrue(store.items.first { $0.id == "image" }?.liked == true)
        for scheme in [ColorScheme.light, .dark] {
            for selection in [nil, "image"] as [String?] {
                store.selection = selection
                let name = "box-\(selection == nil ? "unselected" : "selected")"
                    + "-\(scheme == .light ? "light" : "dark")"
                let bitmap = try await render(store: store, media: media, scheme: scheme,
                    waitsForImage: true, captureName: name)
                XCTAssertEqual(store.selectedItem?.id, selection)
                try write(bitmap, name: name)
            }
        }
    }

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
        store: BoxBrowserStore, media: BoxBrowserMedia, scheme: ColorScheme, waitsForImage: Bool,
        captureName: String? = nil
    ) async throws -> NSBitmapImageRep {
        _ = NSApplication.shared
        var mounted = false
        let probe = LayoutProbe()
        let snapshot = OverviewSnapshot(history: [], live: nil, now: .now)
        let host = NSHostingView(rootView:
            BoxBrowserView(store: store, media: media, sidebar: AnyView(
                OverviewSidebar(snapshot: snapshot, selection: .box, historyState: .loaded,
                    connectionState: .connected, onSelect: { _ in }, onSettings: {}, onRefresh: {},
                    boxScope: store.scope, boxScopes: AnyView(BoxCollectionsSidebar(store: store)),
                    onSelectBoxScope: { store.scope = $0 })))
                .environment(\.colorScheme, scheme)
                .environment(\.layoutProbe, probe)
                .onAppear { mounted = true })
        host.sizingOptions = []
        let screen = try XCTUnwrap(NSScreen.main).visibleFrame
        let size = NSSize(width: min(1120, screen.width - 40), height: min(650, screen.height - 100))
        let window = NSWindow(contentRect: NSRect(origin: screen.origin, size: size),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        window.contentView = host
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try await waitForCondition { mounted && store.didLoad && !store.isLoading && window.toolbar != nil }
        if waitsForImage { try await waitForCondition { media.thumbnails["image"] != nil } }
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.size.height = min(frame.height, screen.height)
        frame.origin = NSPoint(x: screen.minX + 20, y: screen.maxY - frame.height)
        window.setFrame(frame, display: true)
        XCTAssertLessThanOrEqual(window.frame.height, screen.height)
        host.layoutSubtreeIfNeeded()
        for collection in store.collections {
            XCTAssertNotNil(probe.anchors["box.collection.\(collection.id)"])
        }
        if let item = store.selectedItem {
            XCTAssertNotNil(probe.anchors["box.like.\(item.id)"])
        }
        window.displayIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        if let captureName { try await capture(window, name: captureName) }
        XCTAssertGreaterThanOrEqual(bitmap.pixelsWide, Int(size.width))
        XCTAssertGreaterThanOrEqual(bitmap.pixelsHigh, Int(size.height))
        XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 8, y: 8)).alphaComponent, 1, accuracy: 0.01,
            "The Box background must fill the window in every state")
        return bitmap
    }

    private func capture(_ window: NSWindow, name: String) async throws {
        guard let directory = ProcessInfo.processInfo.environment["HIBOSS_SNAPSHOT_DIR"] else { return }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(window.windowNumber),
            URL(fileURLWithPath: directory).appendingPathComponent("\(name)-window.png").path]
        try capture.run()
        try await waitForCondition { !capture.isRunning }
        XCTAssertEqual(capture.terminationStatus, 0)
    }

    private func write(_ bitmap: NSBitmapImageRep, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["HIBOSS_SNAPSHOT_DIR"] else { return }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url.appendingPathComponent("\(name).png"))
    }
}
