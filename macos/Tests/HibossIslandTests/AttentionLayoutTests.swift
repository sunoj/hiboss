// Renders the real attention workspace at constrained sizes with long deployment text.
// Exports: AttentionLayoutTests for native composer geometry and wrapping regressions.
// Dependencies: AppKit, SwiftUI, XCTest, AttentionPreview fixtures.

import AppKit
import SwiftUI
import XCTest
import HibossKit
@testable import HibossIsland

@MainActor
final class AttentionLayoutTests: XCTestCase {
    func testReplyEditorFitsSmallAndWideWindows() async throws {
        for size in [NSSize(width: 480, height: 400), NSSize(width: 760, height: 480),
                     NSSize(width: 960, height: 560), NSSize(width: 1100, height: 640)] {
            try await verifyWorkspace(size: size)
        }
    }

    func testFailedHistoryReplyFitsAShortWindowInBothAppearances() async throws {
        let message = AttentionTestSupport.ask(id: "history", body: String(repeating: "Long context. ", count: 40),
            options: ["Approve", "Wait"], sessionStatus: "waiting")
        let reply = AttentionReplyState()
        reply.drafts[message.id] = "Please investigate first."
        await reply.send("Please investigate first.", for: message.id) { _, _ in false }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let host = NSHostingView(rootView: HistoryMessageDetail(message: message, reply: reply) { _ in false })
            host.sizingOptions = []
            host.appearance = NSAppearance(named: appearance)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 320),
                styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(350))
            host.layoutSubtreeIfNeeded()
            assertEditorFits(host)
        }
    }

    private func verifyWorkspace(size: NSSize) async throws {
        let flow = OptionFlowStore()
        flow.connect(api: ScriptedBossAPI(
            messages: [], history: AttentionPreview.populated(now: Date()).map(\.message)
        ))
        defer { flow.disconnect() }
        let host = NSHostingView(rootView: MainView(settings: AppSettings(), flow: flow))
        host.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(350))
        host.layoutSubtreeIfNeeded()
        assertEditorFits(host)
    }

    private func assertEditorFits(_ host: NSView) {
        let editors = descendants(of: host).compactMap { $0 as? NSTextField }.filter { $0.isEditable }
        XCTAssertFalse(editors.isEmpty, "The reply editor must exist")
        for editor in editors {
            let frame = editor.convert(editor.bounds, to: host)
            XCTAssertGreaterThan(frame.width, 100)
            XCTAssertTrue(host.bounds.insetBy(dx: -1, dy: -1).contains(frame),
                          "Reply editor \(frame) must fit \(host.bounds)")
        }
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

}
