// Hosts Box in the production main window to check stable empty and paginated layouts.
// Exports BoxStableRefreshTests for cached reads, toolbar controls, and retry annotations.
// Dependencies: AppKit, SwiftUI, XCTest, and deterministic Box browser fixtures.

import AppKit
import HibossKit
import SwiftUI
import Vision
import XCTest
@testable import HibossIsland

@MainActor
final class BoxStableRefreshTests: XCTestCase {
    func testEmptyAndPopulatedBoxKeepLayoutAndControlsDuringRefresh() async throws {
        for scheme in [ColorScheme.light, .dark] {
            for items in [[], [BoxBrowserFixtures.item("first", text: "Reference")]] {
                try await heldRefresh(items: items, scheme: scheme)
            }
        }
    }

    private func heldRefresh(items: [BoxItem], scheme: ColorScheme) async throws {
        let api = ScriptedBoxBrowser(pages: [BoxPage(items: items,
            nextCursor: items.isEmpty ? nil : "next")])
        let store = BoxBrowserStore { api }
        let media = BoxBrowserMedia { api }
        let probe = LayoutProbe()
        defer { media.reset() }
        let window = try await show(store: store, media: media, scheme: scheme, probe: probe)
        defer { window.close() }
        let host = try XCTUnwrap(window.contentView)
        try await waitForCondition { store.didLoad && !store.isLoading }
        let root = try XCTUnwrap(window.contentView?.superview)
        let table = probe.anchors["box.item.first"].flatMap(tableContaining)
        if !items.isEmpty { XCTAssertNotNil(table, "Inspect the Box table, including its pagination row") }
        let rowCount = table?.numberOfRows
        let tableFrame = table?.convert(table?.bounds ?? .zero, to: host)
        let controls = descendants(root).compactMap { $0 as? NSButton }.map(\.isEnabled)
        XCTAssertFalse(controls.isEmpty, "Include the native toolbar controls")
        let status = try XCTUnwrap(probe.anchors["box.read-status"])
        let statusFrame = status.convert(status.bounds, to: root)
        XCTAssertEqual(status.convert(status.bounds, to: nil).minY,
            window.contentLayoutRect.minY, accuracy: 1, "The status bar stays at the window bottom")
        await api.holdNextRead()
        let refresh = Task { await store.refresh() }
        await api.waitForHeldRead()
        let early = ContinuousClock.now.advanced(by: .milliseconds(100))
        try await waitForCondition { ContinuousClock.now >= early }
        XCTAssertFalse(try words(root).contains("Updating"), "Stay quiet before the 300 ms delay")
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(400))
        try await waitForCondition { ContinuousClock.now >= deadline }
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(descendants(host).compactMap { $0 as? NSProgressIndicator }.isEmpty,
            "Cached Box results must not become a spinner or insert a progress row")
        XCTAssertEqual(table?.numberOfRows, rowCount, "Keep sections and pagination mounted")
        XCTAssertEqual(table?.convert(table?.bounds ?? .zero, to: host), tableFrame)
        XCTAssertEqual(descendants(root).compactMap { $0 as? NSButton }.map(\.isEnabled), controls)
        XCTAssertEqual(status.convert(status.bounds, to: root), statusFrame, "Reserve the status geometry")
        XCTAssertTrue(try words(root).contains("Updating"), "Show only the delayed compact status")
        XCTAssertEqual(store.items, items)
        let name = "box-\(items.isEmpty ? "empty" : "list")-\(scheme)"
        try capture(window, name: name + "-refresh")
        await api.releaseRead(BoxPage(items: items, nextCursor: items.isEmpty ? nil : "next"))
        await refresh.value
        try await BoxWindowCaptureSupport.settle(window)
        try capture(window, name: name + "-settled")
    }

    func testFailedRefreshKeepsEmptyStateAndOffersCompactRetry() async throws {
        let api = ScriptedBoxBrowser(pages: [BoxPage(items: [])])
        let store = BoxBrowserStore { api }
        let media = BoxBrowserMedia { api }
        defer { media.reset() }
        let window = try await show(store: store, media: media, scheme: .light, probe: LayoutProbe())
        defer { window.close() }
        try await waitForCondition { store.hasResult && !store.isLoading }
        let root = try XCTUnwrap(window.contentView?.superview)
        await api.setReadFailure(true)
        await store.refresh()
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(200))
        try await waitForCondition { ContinuousClock.now >= deadline }
        let content = try words(root)
        XCTAssertTrue(content.contains(L("Your Box is empty")), content)
        XCTAssertTrue(content.contains(L("Update failed")), content)
        XCTAssertFalse(content.contains(L("Box Unavailable")), content)
        try capture(window, name: "box-empty-failed-retry")
        await api.setReadFailure(false)
        await api.holdNextRead()
        try clickRetry(in: root, window: window)
        try await waitForCondition { store.isLoading }
        await api.waitForHeldRead()
        XCTAssertNotNil(store.error, "Keep the failed annotation while retry is in flight")
        XCTAssertTrue(store.items.isEmpty)
        await api.releaseRead(BoxPage(items: []))
        try await waitForCondition { !store.isLoading }
        XCTAssertNil(store.error)
        XCTAssertTrue(store.hasResult)
    }

    private func show(store: BoxBrowserStore, media: BoxBrowserMedia,
                      scheme: ColorScheme, probe: LayoutProbe) async throws -> NSWindow {
        let host = NSHostingView(rootView: MainView(settings: AppSettings(), flow: OptionFlowStore(),
            initialDestination: .box, previewHistory: [], boxStore: store, boxMedia: media,
            panelsModel: PanelsModel(demoMode: true, autoload: false))
            .environment(\.colorScheme, scheme).environment(\.layoutProbe, probe))
        host.sizingOptions = []
        let window = try await StableWindowSupport.show(host, scheme: scheme)
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func words(_ view: NSView) throws -> String {
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
    }

    private func capture(_ window: NSWindow, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["HIBOSS_BOX_REFRESH_SHOTS"] else { return }
        try BoxWindowCaptureSupport.capture(window, directory: directory, name: name)
    }

    private func descendants(_ view: NSView) -> [NSView] {
        StableWindowSupport.descendants(view)
    }

    private func tableContaining(_ view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        return view.superview.flatMap(tableContaining)
    }

    private func clickRetry(in view: NSView, window: NSWindow) throws {
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
        let text = try XCTUnwrap(request.results?.compactMap { $0.topCandidates(1).first }.first {
            $0.string.contains(L("Retry"))
        })
        let range = try XCTUnwrap(text.string.range(of: L("Retry")))
        let bounds = try XCTUnwrap(text.boundingBox(for: range)).boundingBox
        let y = view.isFlipped ? 1 - bounds.midY : bounds.midY
        let point = view.convert(NSPoint(x: view.bounds.width * bounds.midX,
            y: view.bounds.height * y), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point,
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1))
            window.sendEvent(event)
        }
    }
}
