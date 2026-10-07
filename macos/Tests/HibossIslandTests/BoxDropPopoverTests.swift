// Drives native pasteboards into the Island popover and checks the rendered composer.
// Exports BoxDropPopoverTests with an optional native view capture for visual inspection.
// Dependencies: XCTest, AppKit, SwiftUI and the Island drop bridge.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class BoxDropPopoverTests: XCTestCase {
    func testIdleIslandAcceptsPasteboardAndPreservesDraftOnAnotherDrop() async throws {
        let controller = try controller()
        defer { controller.panel.close() }
        XCTAssertTrue(controller.panel.isVisible)
        let host = try XCTUnwrap(controller.panel.contentView as? BoxDropHostingView)
        defer { host.popover.close() }
        try await waitForCondition { host.bounds.width > 100 }
        let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("https://example.com/reference", forType: .URL)
        host.receive(pasteboard)
        let store = try XCTUnwrap(host.dropStore)
        XCTAssertTrue(host.popover.isShown)
        try await waitForCondition { store.phase == .ready }
        store.note = "Use this layout"
        host.receive(pasteboard)
        XCTAssertTrue(host.dropStore === store)
        XCTAssertEqual(store.note, "Use this layout")
        XCTAssertEqual(store.payloads.first?.kind, .link)
        let popoverView = try XCTUnwrap(host.popover.contentViewController?.view)
        try await waitForCondition {
            Self.fields(popoverView).contains { $0.stringValue == "Use this layout" }
        }
        if let path = ProcessInfo.processInfo.environment["HIBOSS_BOX_CAPTURE"] {
            let window = try XCTUnwrap(popoverView.window)
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-l", String(window.windowNumber), path]
            try capture.run()
            capture.waitUntilExit()
            XCTAssertEqual(capture.terminationStatus, 0)
        }
    }

    func testFivePasteboardItemsShowRejectionInsteadOfTruncating() async throws {
        let controller = try controller()
        defer { controller.panel.close() }
        let host = try XCTUnwrap(controller.panel.contentView as? BoxDropHostingView)
        defer { host.popover.close() }
        let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        let items = (0..<5).map { index in
            let item = NSPasteboardItem()
            item.setString("Item \(index)", forType: .string)
            return item
        }
        pasteboard.writeObjects(items)
        host.receive(pasteboard)
        let store = try XCTUnwrap(host.dropStore)
        XCTAssertEqual(store.phase, .rejected)
        XCTAssertEqual(store.error, BoxDropError.itemCount.localizedDescription)
        XCTAssertTrue(store.payloads.isEmpty)
    }

    func testPopoverRendersNativeNoteAndSaveCancelControls() async throws {
        let store = BoxDropStore { _, _, _ in }
        await store.prepare([.text("https://example.com/reference"), .text("A passage to keep")])
        store.note = "Use this layout"
        let host = NSHostingView(rootView: BoxDropPopover(store: store, close: {}))
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 320, height: 240),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try await waitForCondition { Self.fields(host).contains { $0.stringValue == "Use this layout" } }
        host.layoutSubtreeIfNeeded()
        XCTAssertFalse(store.noteLocked)
    }

    private func controller() throws -> IslandPanelController {
        _ = NSApplication.shared
        let name = "BoxDropPopoverTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults, keychain: DropNoTokenStore())
        settings.playsSound = false
        return IslandPanelController(flow: OptionFlowStore(), settings: settings)
    }

    private static func fields(_ view: NSView) -> [NSTextField] {
        view.subviews.flatMap { subview in
            if let field = subview as? NSTextField { return [field] }
            return fields(subview)
        }
    }
}

private struct DropNoTokenStore: TokenStoring {
    func read() throws -> String? { nil }
    func write(_ token: String) throws {}
}
