// Drives production Box row selection, keyboard shortcuts and the native delete dialog.
// Exports: BoxBrowserKeyboardTests; fixtures are hosted in a real AppKit window.
// Dependencies: SwiftUI, AppKit, Quartz, Vision and ScriptedBoxBrowser.

import AppKit
import HibossKit
import Quartz
import SwiftUI
import Vision
import XCTest
@testable import HibossIsland

@MainActor
final class BoxBrowserKeyboardTests: XCTestCase {
    func testSelectionArrowsSpaceAndDeleteConfirmationInHostedWindow() async throws {
        _ = NSApplication.shared
        let first = BoxBrowserFixtures.item("first", text: "First reference",
            createdAt: "2026-10-12T08:00:00Z")
        let second = BoxBrowserFixtures.item("second", text: "Second reference",
            createdAt: "2026-10-12T07:00:00Z")
        let api = ScriptedBoxBrowser(pages: [BoxPage(items: [first, second])])
        let store = BoxBrowserStore { api }
        let media = BoxBrowserMedia { api }
        let probe = LayoutProbe()
        defer { media.reset() }
        let host = NSHostingView(rootView: NavigationStack { BoxBrowserView(store: store, media: media) }
            .environment(\.layoutProbe, probe))
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 60, y: 60, width: 900, height: 650),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try await waitForCondition { store.didLoad && !store.isLoading }
        try await verifyKeyboard(store: store, host: host, window: window, probe: probe)
        try await verifyDeleteConfirmation(store: store, api: api, item: first, host: host, window: window)
    }

    private func verifyKeyboard(
        store: BoxBrowserStore, host: NSView, window: NSWindow, probe: LayoutProbe
    ) async throws {
        var phase = "empty detail"
        do {
            let initial = try recognize(host).map(\.text)
            XCTAssertTrue(initial.contains(L("Select a Box item")))
            XCTAssertFalse(initial.contains(L("Open")))
            XCTAssertFalse(initial.contains(L("Delete…")))
            let row = try XCTUnwrap(probe.anchors["box.item.first"])
            let table = try XCTUnwrap(tableView(host))
            let point = row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: table)
            let index = table.row(at: point)
            XCTAssertGreaterThanOrEqual(index, 0)
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                    continuation.resume()
                }
            }
            window.makeFirstResponder(table)
            phase = "row selection"
            try await waitForCondition { store.selection == "first" }
            try key("\u{f701}", code: 125, window: window)
            phase = "down arrow"
            try await waitForCondition { store.selection == "second" }
            XCTAssertEqual(store.selectedItem?.text, "Second reference")
            try key("\u{f700}", code: 126, window: window)
            phase = "up arrow"
            try await waitForCondition { store.selection == "first" }
            try key(" ", code: 49, window: window)
            phase = "Quick Look"
            try await waitForCondition { QLPreviewPanel.sharedPreviewPanelExists() &&
                QLPreviewPanel.shared()?.isVisible == true }
            QLPreviewPanel.shared()?.orderOut(nil)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(table)
        } catch {
            XCTFail("Keyboard phase \(phase) failed: \(error)")
            throw error
        }
    }

    private func verifyDeleteConfirmation(
        store: BoxBrowserStore, api: ScriptedBoxBrowser, item: BoxItem, host: NSView, window: NSWindow
    ) async throws {
        try key("\u{7f}", code: 51, window: window)
        try await waitForCondition { store.pendingDelete?.id == "first" && window.attachedSheet != nil }
        let sheet = try XCTUnwrap(window.attachedSheet)
        let words = try await recognizeWindow(sheet).joined(separator: " ")
        XCTAssertTrue(words.contains("First reference"), words)
        XCTAssertTrue(words.contains(L("Agents will no longer be able to read this item.")), words)
        let beforeConfirmation = await api.deleted
        XCTAssertTrue(beforeConfirmation.isEmpty)
        try key("\r", code: 36, window: sheet)
        try await waitForCondition { window.attachedSheet == nil }
        let afterDefault = await api.deleted
        XCTAssertTrue(afterDefault.isEmpty)
        XCTAssertTrue(store.items.contains(item))
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(try XCTUnwrap(tableView(host)))
        try key("\u{7f}", code: 51, window: window)
        try await waitForCondition { window.attachedSheet != nil }
        let confirmed = try XCTUnwrap(window.attachedSheet)
        let delete = try XCTUnwrap(button(named: L("Delete"), in: confirmed.contentView))
        delete.performClick(nil)
        try await waitForCondition { !store.items.contains(item) }
        let deleted = await api.deleted
        XCTAssertEqual(deleted, ["first"])
        XCTAssertNil(store.selectedItem)
    }

    private func button(named title: String, in root: NSView?) -> NSButton? {
        guard let root else { return nil }
        if let button = root as? NSButton, button.title == title { return button }
        return root.subviews.lazy.compactMap { self.button(named: title, in: $0) }.first
    }

    private func recognizeWindow(_ window: NSWindow) async throws -> [String] {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: file) }
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), file.path]
        try capture.run()
        try await waitForCondition { !capture.isRunning }
        XCTAssertEqual(capture.terminationStatus, 0)
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(url: file).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    private func key(_ characters: String, code: UInt16, window: NSWindow) throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: code))
        if !window.performKeyEquivalent(with: event) { window.sendEvent(event) }
    }

    private func tableView(_ root: NSView) -> NSTableView? {
        if let table = root as? NSTableView { return table }
        return root.subviews.compactMap(tableView).first
    }

    private func recognize(_ host: NSView) throws -> [(text: String, bounds: CGRect)] {
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["en-US"]
        do {
            try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
        } catch {
            XCTFail("Text recognition failed for \(host.bounds): \(error)")
            throw error
        }
        return (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map { ($0.string, observation.boundingBox) }
        }
    }
}
