// Exercises the native sidebar search control in both system appearances.
// Exports: SidebarFormattingTests with light/dark hosted regression checks.
// Dependencies: AppKit, SwiftUI, XCTest, and production OverviewSidebar.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class SidebarFormattingTests: XCTestCase {
    func testSearchIsNativeAndSettingsLeftTheSidebarInBothAppearances() async throws {
        _ = NSApplication.shared
        for scheme in [ColorScheme.light, .dark] {
            let sidebar = OverviewSidebar(snapshot: OverviewSnapshot(history: [], live: nil, now: .now),
                selection: .today, historyState: .loaded, connectionState: .connected,
                onSelect: { _ in }, onSettings: {}, onRefresh: {})
            let probe = LayoutProbe()
            var mounted = false
            let host = NSHostingView(rootView: sidebar.environment(\.colorScheme, scheme)
                .environment(\.layoutProbe, probe)
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
            XCTAssertEqual(search?.placeholderAttributedString?.string ?? search?.placeholderString,
                L("Find a session"))
            let placeholder = try XCTUnwrap(search?.placeholderAttributedString)
            XCTAssertEqual(placeholder.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
                .secondaryLabelColor, "The native placeholder must use readable semantic label contrast")
            // Settings lives in the toolbar; the sidebar no longer carries a footer row.
            XCTAssertNil(probe.anchors["sidebar.settingsRow"])
        }
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    func testNativeSearchTypingAndClearingUpdateTheBinding() {
        var text = "initial"
        let binding = Binding(get: { text }, set: { text = $0 })
        let coordinator = SessionSearchField.Coordinator(text: binding)
        let field = NSSearchField()
        for query in ["house", ""] {
            field.stringValue = query
            coordinator.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification,
                object: field))
            XCTAssertEqual(text, query)
        }
    }

    func testDecisionBadgeIsAbsentAtZeroAndWhileUnavailableButPresentForOpenDecisions() {
        let message = AttentionTestSupport.ask(id: "decision", options: ["Ship", "Hold"])
        for (loaded, inputs, expected) in [(true, [], nil), (false, [message], nil),
                                           (true, [message], "1")] as [(Bool, [HistoryMessage], String?)] {
            let snapshot = OverviewSnapshot(history: inputs, live: nil, now: AttentionTestSupport.now,
                requiredInputs: inputs, requiredInputLoaded: loaded)
            let sidebar = OverviewSidebar(snapshot: snapshot, selection: .today,
                historyState: .loaded, connectionState: .connected,
                onSelect: { _ in }, onSettings: {}, onRefresh: {})
            XCTAssertEqual(sidebar.decisionBadge, expected)
        }
    }
}
