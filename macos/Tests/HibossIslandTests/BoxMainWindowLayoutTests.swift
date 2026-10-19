// Exercises Box geometry in MainView with the native main scene's window chrome.
// Exports: BoxMainWindowLayoutTests; optional compositor captures include the entire window.
// Dependencies: AppKit, SwiftUI, XCTest, LayoutProbe and deterministic Box fixtures.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class BoxMainWindowLayoutTests: XCTestCase {
    func testToolbarControlsDoNotOverlapAt1402InBothAppearances() async throws {
        guard try await BoxAppSDKTestHost.runHere(#function) else { return }
        for scheme in [ColorScheme.light, .dark] {
            try await withWindow(width: 1402, scheme: scheme) { window, probe in
                try self.checkToolbar(window, probe: probe, compact: false)
                try await self.captureMenus(window, probe: probe, scheme: scheme)
            }
        }
    }

    func testToolbarControlsDoNotOverlapAtMinimumWidthInBothAppearances() async throws {
        guard try await BoxAppSDKTestHost.runHere(#function) else { return }
        for scheme in [ColorScheme.light, .dark] {
            try await withWindow(width: 480, scheme: scheme) { window, probe in
                try self.checkToolbar(window, probe: probe, compact: true)
            }
        }
    }

    func testMoreMenuUsesContentWidthInBothAppearances() async throws {
        guard try await BoxAppSDKTestHost.runHere(#function) else { return }
        for scheme in [ColorScheme.light, .dark] {
            try await withWindow(width: 1402, scheme: scheme) { _, probe in
                let more = try self.frame("box.more", probe: probe)
                let actions = try self.frame("box.actions", probe: probe)
                XCTAssertGreaterThan(more.width, 30)
                XCTAssertLessThan(more.width, 120, "More must size like the neighboring buttons")
                XCTAssertLessThan(more.width, actions.width / 2)
            }
        }
    }

    func testInformationUsesSharedLeftAlignedColumnsInBothAppearances() async throws {
        guard try await BoxAppSDKTestHost.runHere(#function) else { return }
        for scheme in [ColorScheme.light, .dark] {
            try await withWindow(width: 1402, scheme: scheme) { _, probe in
                let information = try self.frame("box.information", probe: probe)
                let authorLabel = try self.frame("box.information.Author.label", probe: probe)
                let authorValue = try self.frame("box.information.Author.value", probe: probe)
                XCTAssertLessThan(authorLabel.minX - information.minX, 40)
                for title in ["Author", "Project", "Tags", "Format", "Added"] {
                    let label = try self.frame("box.information.\(title).label", probe: probe)
                    let value = try self.frame("box.information.\(title).value", probe: probe)
                    XCTAssertEqual(label.maxX, authorLabel.maxX, accuracy: 1, title)
                    XCTAssertEqual(value.minX, authorValue.minX, accuracy: 1, title)
                    XCTAssertGreaterThanOrEqual(value.minX - label.maxX, 6, title)
                    XCTAssertLessThanOrEqual(value.minX - label.maxX, 16, title)
                }
            }
        }
    }

    func testCollectionsShareSidebarAndBottomActionsAtDefaultAnd900Widths() async throws {
        guard try await BoxAppSDKTestHost.runHere(#function) else { return }
        for scheme in [ColorScheme.light, .dark] {
            for width in [CGFloat(1320), 900] {
                try await checkCollectionsWindow(width: width, scheme: scheme)
            }
        }
    }

    private func checkCollectionsWindow(width: CGFloat, scheme: ColorScheme) async throws {
        let api = ScriptedBoxBrowser(media: BoxBrowserFixtures.imageData())
        let store = BoxBrowserStore { api }
        let media = BoxBrowserMedia { api }
        defer { media.reset() }
        await store.refresh()
        store.selection = "image"
        let probe = LayoutProbe()
        let window = try await BoxMainWindowLayoutSupport.show(store: store, media: media,
            probe: probe, width: width, scheme: scheme, height: 820)
        defer { window.close() }
        let settings = try frame("sidebar.settingsRow", probe: probe)
        XCTAssertEqual(settings.minY, window.contentLayoutRect.minY + 16, accuracy: 1)
        let collection = try frame("box.collection.design", probe: probe)
        let liked = try frame("box.scope.liked", probe: probe)
        XCTAssertGreaterThan(collection.minY, settings.maxY)
        XCTAssertGreaterThan(liked.minY, collection.maxY)
        let actions = try frame("box.actions", probe: probe)
        let like = try frame("box.like.image", probe: probe)
        let more = try frame("box.more", probe: probe)
        XCTAssertTrue(actions.contains(like))
        XCTAssertTrue(actions.contains(more))
        XCTAssertLessThan(like.maxX, more.minX)
        XCTAssertTrue(window.contentLayoutRect.contains(actions))
        if let directory = ProcessInfo.processInfo.environment["HIBOSS_BOX_WINDOW_SHOTS"] {
            let name = "box-collections-\(Int(width))-\(scheme == .light ? "light" : "dark")"
            try BoxWindowCaptureSupport.capture(window, directory: directory, name: name)
        }
    }

    private func withWindow(width: CGFloat, scheme: ColorScheme,
                            check: (NSWindow, LayoutProbe) async throws -> Void) async throws {
        let item = BoxBrowserFixtures.items[0]
        let api = ScriptedBoxBrowser(pages: [BoxPage(items: [item])],
            media: BoxBrowserFixtures.imageData())
        let store = BoxBrowserStore { api }
        let media = BoxBrowserMedia { api }
        defer { media.reset() }
        await store.refresh()
        store.selection = item.id
        let probe = LayoutProbe()
        let window = try await BoxMainWindowLayoutSupport.show(store: store, media: media,
            probe: probe, width: width, scheme: scheme)
        defer { window.close() }
        try await check(window, probe)
        if let directory = ProcessInfo.processInfo.environment["HIBOSS_BOX_WINDOW_SHOTS"] {
            let name = "box-main-\(Int(width))-\(scheme == .light ? "light" : "dark")"
            try BoxWindowCaptureSupport.capture(window, directory: directory, name: name)
        }
    }

    private func checkToolbar(_ window: NSWindow, probe: LayoutProbe, compact: Bool) throws {
        let toolbar = try XCTUnwrap(window.toolbar)
        let visibleItems = try XCTUnwrap(toolbar.visibleItems)
        let ids = compact ? ["box.compact-filters", "workspace.live", "workspace.refresh"]
            : ["box.filters", "box.source", "workspace.live", "workspace.refresh"]
        var controls: [(String, NSRect)] = []
        var anchors: [NSView] = []
        for id in ids {
            guard let anchor = probe.anchors[id], anchor.window === window,
                  !anchor.isHiddenOrHasHiddenAncestor, !anchor.bounds.isEmpty else {
                XCTAssertTrue(compact && visibleItems.count < toolbar.items.count,
                    "\(id) must be visible or in native toolbar overflow")
                continue
            }
            controls.append((id, anchor.convert(anchor.bounds, to: nil)))
            anchors.append(anchor)
        }
        let root = try XCTUnwrap(window.contentView?.superview)
        if let search = BoxWindowCaptureSupport.descendants(root).first(where: { $0 is NSSearchField }),
           !search.isHiddenOrHasHiddenAncestor, !search.bounds.isEmpty {
            controls.append(("search", search.convert(search.bounds, to: nil)))
            anchors.append(search)
        } else {
            XCTAssertTrue(toolbar.items.contains { $0.label == "Search" })
        }
        XCTAssertGreaterThanOrEqual(controls.count, compact ? 1 : 5)
        for item in visibleItems {
            guard let view = item.view, view.window === window, !view.isHiddenOrHasHiddenAncestor,
                  !view.bounds.isEmpty,
                  !anchors.contains(where: { $0.isDescendant(of: view) }) else { continue }
            controls.append((item.label, view.convert(view.bounds, to: nil)))
        }
        for (index, first) in controls.enumerated() {
            XCTAssertTrue(NSRect(origin: .zero, size: window.frame.size).contains(first.1), first.0)
            for second in controls.dropFirst(index + 1) {
                XCTAssertFalse(first.1.intersects(second.1),
                    "\(first.0) \(first.1) overlaps \(second.0) \(second.1)")
            }
        }
    }

    private func captureMenus(_ window: NSWindow, probe: LayoutProbe, scheme: ColorScheme) async throws {
        guard let directory = ProcessInfo.processInfo.environment["HIBOSS_BOX_WINDOW_SHOTS"] else { return }
        let appearance = scheme == .light ? "light" : "dark"
        let menus: [(String, [String])] = [
            ("box.filters", [L("All")] + BoxItem.Kind.allCases.map(\.filterTitle)),
            ("box.source", BoxAuthorFilter.allCases.map { L("Source:") + " " + $0.title }),
            ("box.more", [BoxPaneAction.open, .quickLook, .share, .editNote, .delete].map(\.title))
        ]
        for (id, titles) in menus {
            try await BoxWindowCaptureSupport.captureMenu(XCTUnwrap(probe.anchors[id]), window: window,
                directory: directory, name: "box-main-1402-\(appearance)-\(id)", expectedTitles: titles)
        }
    }

    private func frame(_ id: String, probe: LayoutProbe) throws -> NSRect {
        let anchor = try XCTUnwrap(probe.anchors[id], id)
        XCTAssertNotNil(anchor.window, id)
        XCTAssertFalse(anchor.bounds.isEmpty, id)
        return anchor.convert(anchor.bounds, to: nil)
    }
}
