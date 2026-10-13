// Verifies native Box toolbar controls and captures all review states of the full MainView.
// Exports: BoxWindowCaptureTests; HIBOSS_BOX_WINDOW_SHOTS enables compositor evidence.
// Dependencies: AppKit, SwiftUI, XCTest and deterministic Box media fixtures.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class BoxWindowCaptureTests: XCTestCase {
    func testSidebarDoesNotLabelUnavailableDecisionCountsAsLoading() {
        let sidebar = OverviewSidebar(snapshot: OverviewSnapshot(history: [], live: nil, now: .now),
            selection: .box, historyState: .loaded, connectionState: .connected,
            onSelect: { _ in }, onSettings: {}, onRefresh: {})
        XCTAssertNil(sidebar.decisionBadge)
    }

    func testSettledMainWindowHasNativeToolbarAndAllReviewStates() async throws {
        let api = ScriptedBoxBrowser(pages: [BoxPage(items: Self.items)],
            media: BoxBrowserFixtures.imageData(), mediaByID: ["video": try await BoxVideoFixture.data()])
        let store = BoxBrowserStore { api }
        let media = BoxBrowserMedia { api }
        defer { media.reset() }
        await store.refresh()
        for scheme in [ColorScheme.light, .dark] {
            let probe = LayoutProbe()
            let window = try await BoxWindowCaptureSupport.show(
                store: store, media: media, scheme: scheme, probe: probe)
            defer { window.close() }
            let root = try XCTUnwrap(window.contentView?.superview)
            let views = BoxWindowCaptureSupport.descendants(root)
            XCTAssertTrue(views.contains { $0 is NSSegmentedControl })
            XCTAssertTrue(views.contains { $0 is NSSearchField })
            let popup = try XCTUnwrap(probe.anchors["box.source"])
            try await BoxWindowCaptureSupport.captureMenu(popup, window: window,
                directory: nil, name: "source-validation")
            for item in store.items {
                let thumbnail = try XCTUnwrap(probe.anchors["box.thumbnail.\(item.id)"])
                XCTAssertEqual(thumbnail.bounds.width, 44, accuracy: 0.5)
                XCTAssertEqual(thumbnail.bounds.height, 44, accuracy: 0.5)
            }
            try await captureStates(store: store, window: window, popup: popup, scheme: scheme)
        }
    }

    private func captureStates(store: BoxBrowserStore, window: NSWindow,
                               popup: NSView, scheme: ColorScheme) async throws {
        let directory = ProcessInfo.processInfo.environment["HIBOSS_BOX_WINDOW_SHOTS"]
        let appearance = scheme == .light ? "light" : "dark"
        for selection in [nil, "image", "text"] as [String?] {
            store.selection = selection
            try await BoxWindowCaptureSupport.settle(window)
            XCTAssertEqual(store.selectedItem?.id, selection)
            if let directory {
                try BoxWindowCaptureSupport.capture(window, directory: directory,
                    name: "box-\(selection ?? "unselected")-\(appearance)")
            }
        }
        let item = try XCTUnwrap(store.selectedItem)
        store.requestDelete(item)
        try await waitForCondition { window.attachedSheet != nil }
        if let directory {
            try await BoxWindowCaptureSupport.settle(window)
            try BoxWindowCaptureSupport.capture(window, directory: directory,
                name: "box-delete-\(appearance)")
        }
        store.pendingDelete = nil
        try await waitForCondition { window.attachedSheet == nil }
        if let directory {
            try await BoxWindowCaptureSupport.captureMenu(popup, window: window,
                directory: directory, name: "box-source-\(appearance)")
        }
    }

    private static var items: [BoxItem] {
        let now = Date.now
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        let dates = [now.addingTimeInterval(-37), now.addingTimeInterval(-180),
            yesterday, now.addingTimeInterval(-7200), now.addingTimeInterval(-120)]
        return zip(BoxBrowserFixtures.items, dates).map { item, date in
            BoxBrowserFixtures.item(item.id, kind: item.kind, text: item.text, url: item.url,
                note: item.note, hasMedia: item.hasMedia, mediaType: item.mediaType,
                mediaBytes: item.mediaBytes, width: item.width, height: item.height,
                author: item.addedBy, createdAt: ISO8601DateFormatter().string(from: date),
                durationMs: item.durationMs)
        }
    }
}
