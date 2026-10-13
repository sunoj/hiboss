// Exercises native sidebar search, footer accessibility, and session text layout.
// Exports: SidebarFormattingTests with light/dark hosted regression checks.
// Dependencies: AppKit, SwiftUI, XCTest, and production OverviewSidebar.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class SidebarFormattingTests: XCTestCase {
    func testSearchIsNativeAndFooterHasNoUnattachedCaption() async throws {
        _ = NSApplication.shared
        for scheme in [ColorScheme.light, .dark] {
            let sidebar = OverviewSidebar(snapshot: OverviewSnapshot(history: [], live: nil, now: .now),
                selection: .today, historyState: .loaded, connectionState: .connected,
                onSelect: { _ in }, onSettings: {}, onRefresh: {})
            var mounted = false
            let host = NSHostingView(rootView: sidebar.environment(\.colorScheme, scheme)
                .onAppear { mounted = true })
            host.sizingOptions = []
            let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 300, height: 780),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            defer { window.close() }
            try await waitForCondition { mounted && !host.subviews.isEmpty }
            host.layoutSubtreeIfNeeded()
            let search = descendants(host).compactMap { $0 as? NSSearchField }.first
            XCTAssertNotNil(search, "Session search must use the native search control")
            XCTAssertEqual(search?.placeholderString, L("Find a session"))
            let labels = accessibilityLabels(host)
            XCTAssertTrue(labels.contains(L("Settings")), "The footer must be mounted")
            XCTAssertFalse(labels.contains(L("Recent messages")))
        }
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private func accessibilityLabels(_ element: any NSAccessibility) -> [String] {
        let children = (element.accessibilityChildren() ?? []).compactMap { $0 as? any NSAccessibility }
        return [element.accessibilityLabel()].compactMap { $0 } + children.flatMap(accessibilityLabels)
    }
}
