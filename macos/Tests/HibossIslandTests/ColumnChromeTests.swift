// Titlebar labels keep the window's appearance after the titlebar turns transparent.
// Exports: ColumnChromeTests; opens one titled window, so it runs through window-run.sh.
// Dependencies: AppKit, SwiftUI, XCTest and the shared waitForCondition helper.

import AppKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class ColumnChromeTests: XCTestCase {
    func testTitlebarLabelsFollowAnAppearanceChange() async throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: Color.clear.columnChrome())
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try await waitForCondition { window.titlebarAppearsTransparent && self.pinned(window) == [.aqua] }

        window.appearance = NSAppearance(named: .darkAqua)
        try await waitForCondition { self.pinned(window) == [.darkAqua] }
    }

    /// Appearances pinned on the titlebar-height children of the window's frame view.
    private func pinned(_ window: NSWindow) -> Set<NSAppearance.Name> {
        guard var root = window.contentView else { return [] }
        while let parent = root.superview { root = parent }
        return Set(root.subviews.filter { $0.bounds.height > 20 && $0.bounds.height < 120 }
            .compactMap { $0.appearance?.name })
    }
}
