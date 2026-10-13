// Exercises compact native toolbar overflow, the deliberate footer, and full-width details.
// Exports: BoxPolishLayoutTests; HIBOSS_BOX_WINDOW_SHOTS saves window and open-menu evidence.
// Dependencies: AppKit, SwiftUI, XCTest, and the production MainView capture harness.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class BoxPolishLayoutTests: XCTestCase {
    func testBoxFitsDefaultAndMinimumWidthsWithReachableNativeFilters() async throws {
        for scheme in [ColorScheme.light, .dark] {
            for width in [CGFloat(960), 480] {
                try await checkWindow(width: width, scheme: scheme)
            }
        }
    }

    func testDetailMetadataFillsPaneAndPrimaryActionsUseOneRow() async throws {
        let probe = LayoutProbe()
        let media = BoxBrowserMedia { nil }
        let host = NSHostingView(rootView: BoxBrowserDetail(item: BoxBrowserFixtures.items[0],
            media: media, busy: false, copied: false, perform: { _ in })
            .environment(\.layoutProbe, probe))
        let window = try await StableWindowSupport.show(host)
        defer { window.close(); media.reset() }
        try checkDetail(probe, window: window)
    }

    private func checkWindow(width: CGFloat, scheme: ColorScheme) async throws {
        let item = BoxBrowserFixtures.item("image", kind: .image,
            note: "Soil boring locations\nMeasurements for the next review.",
            hasMedia: true, mediaType: "image/png")
        let api = ScriptedBoxBrowser(pages: [BoxPage(items: [item])], media: BoxBrowserFixtures.imageData())
        let store = BoxBrowserStore { api }
        let media = BoxBrowserMedia { api }
        defer { media.reset() }
        let probe = LayoutProbe()
        let window = try await BoxWindowCaptureSupport.show(store: store, media: media,
            scheme: scheme, probe: probe, requestedSize: NSSize(width: width, height: 640))
        defer { window.close() }
        XCTAssertEqual(window.frame.width, width, accuracy: 1)
        let root = try XCTUnwrap(window.contentView?.superview)
        let toolbarItems = window.toolbar?.items.map { ($0.label, String(describing: type(of: $0))) } ?? []
        print("Box \(width) toolbar: \(toolbarItems)")
        if let search = BoxWindowCaptureSupport.descendants(root).first(where: { $0 is NSSearchField }),
           !search.isHiddenOrHasHiddenAncestor {
            XCTAssertTrue(window.frameRect(forContentRect: window.contentLayoutRect)
                .insetBy(dx: -1, dy: -1).contains(search.convert(search.bounds, to: nil)))
        } else { XCTAssertTrue(window.toolbar?.items.contains { $0.label == "Search" } == true) }
        try checkFooter(probe, window: window)
        let directory = ProcessInfo.processInfo.environment["HIBOSS_BOX_WINDOW_SHOTS"]
        let name = "box-\(Int(width))-\(scheme == .light ? "light" : "dark")"
        if let directory { try BoxWindowCaptureSupport.capture(window, directory: directory, name: name) }
        try await checkFilters(probe, window: window, directory: directory, name: name)
        store.selection = item.id
        try await BoxWindowCaptureSupport.settle(window)
        let detailWindow = window.attachedSheet ?? window
        try checkDetail(probe, window: detailWindow)
        if let directory {
            try BoxWindowCaptureSupport.capture(window, directory: directory, name: name + "-detail")
        }
        try await BoxWindowCaptureSupport.captureMenu(XCTUnwrap(probe.anchors["box.more"]),
            window: detailWindow, directory: directory, name: name + "-more",
            expectedTitles: [.quickLook, .share, .editNote, .delete]
                .map { (action: BoxPaneAction) in action.title })
    }

    private func checkFooter(_ probe: LayoutProbe, window: NSWindow) throws {
        let footer = try XCTUnwrap(probe.anchors["box.read-status"])
        let count = try XCTUnwrap(probe.anchors["box.item-count"])
        let list = try XCTUnwrap(probe.anchors["box.list"])
        let footerFrame = footer.convert(footer.bounds, to: nil)
        let listFrame = list.convert(list.bounds, to: nil)
        XCTAssertEqual(footerFrame.minY, window.contentLayoutRect.minY, accuracy: 1)
        XCTAssertEqual(listFrame.minY, footerFrame.maxY, accuracy: 1)
        XCTAssertTrue(footerFrame.contains(count.convert(count.bounds, to: nil)))
        let row = try XCTUnwrap(probe.anchors["box.item.image"])
        XCTAssertTrue(listFrame.contains(row.convert(row.bounds, to: nil)))
    }

    private func checkFilters(_ probe: LayoutProbe, window: NSWindow,
                              directory: String?, name: String) async throws {
        if let compact = probe.anchors["box.compact-filters"] {
            XCTAssertTrue(window.frameRect(forContentRect: window.contentLayoutRect)
                .contains(compact.convert(compact.bounds, to: nil)))
            try await BoxWindowCaptureSupport.captureMenu(compact, window: window,
                directory: directory, name: name + "-filters", expectedTitles: [L("Kind"), L("Source:")])
            return
        }
        if window.frame.width < 900 {
            let root = try XCTUnwrap(window.contentView?.superview)
            let overflow = try XCTUnwrap(BoxWindowCaptureSupport.descendants(root).first {
                String(describing: type(of: $0)).contains("ClippedItems")
            }, "Native toolbar overflow must be reachable")
            let menu = try await BoxWindowCaptureSupport.captureMenu(overflow, window: window,
                directory: directory, name: name + "-overflow", expectedTitles: [L("Filter")])
            let filters = try XCTUnwrap(menu.items.first?.submenu, "Overflow preserves the filter menu")
            XCTAssertEqual(filters.items.filter { !$0.isSeparatorItem }.map(\.title),
                [L("Kind"), L("Source:")])
            try BoxWindowCaptureSupport.capturePopupMenu(filters, window: window,
                directory: directory, name: name + "-filters")
            return
        }
        for (id, titles) in [("box.filters", [L("All")] + BoxItem.Kind.allCases.map(\.filterTitle)),
                            ("box.source", BoxAuthorFilter.allCases.map { L("Source:") + " " + $0.title })] {
            let anchor = try XCTUnwrap(probe.anchors[id])
            XCTAssertTrue(window.contentView!.superview!.bounds.contains(
                anchor.convert(anchor.bounds, to: window.contentView!.superview)))
            try await BoxWindowCaptureSupport.captureMenu(anchor, window: window,
                directory: directory, name: name + "-" + id, expectedTitles: titles)
        }
    }

    private func checkDetail(_ probe: LayoutProbe, window: NSWindow) throws {
        let metadata = try XCTUnwrap(probe.anchors["box.information"])
        let actions = try XCTUnwrap(probe.anchors["box.actions"])
        XCTAssertGreaterThan(metadata.bounds.width, 250)
        XCTAssertGreaterThan(metadata.bounds.width, actions.bounds.width - 45)
        XCTAssertLessThan(actions.bounds.height, 30, "Primary actions occupy one row")
        XCTAssertTrue(window.contentLayoutRect.contains(actions.convert(actions.bounds, to: nil)))
    }
}
