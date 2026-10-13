// Installs MainView in the titled, unified window used by the main SwiftUI Window scene.
// Exports: BoxMainWindowLayoutSupport.show; replaces Today with Box after installing and sizing the toolbar.
// Dependencies: AppKit, SwiftUI, XCTest and injectable Box state.

import AppKit
import SwiftUI
import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
enum BoxMainWindowLayoutSupport {
    static func show(store: BoxBrowserStore, media: BoxBrowserMedia, probe: LayoutProbe,
                     width: CGFloat, scheme: ColorScheme) async throws -> NSWindow {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        let controller = NSHostingController(rootView: rootView(store: store, media: media,
            probe: probe, scheme: scheme, destination: .today))
        controller.sizingOptions = []
        let host = controller.view
        let screen = try XCTUnwrap(NSScreen.main).visibleFrame
        XCTAssertGreaterThanOrEqual(screen.width, width)
        XCTAssertGreaterThanOrEqual(screen.height, 903)
        let mask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        let window = NSWindow(contentRect: NSRect(x: screen.minX, y: screen.minY, width: 1320, height: 500),
            styleMask: mask, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        window.titleVisibility = .visible
        window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        host.appearance = window.appearance
        window.contentViewController = controller
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        try await waitForCondition { window.toolbar != nil }
        window.setFrame(NSRect(x: screen.minX + 20, y: screen.maxY - 903, width: width, height: 903),
            display: true)
        try await BoxWindowCaptureSupport.settle(window)
        controller.rootView = rootView(store: store, media: media,
            probe: probe, scheme: scheme, destination: .box)
        try await waitForCondition(timeout: .seconds(5)) {
            probe.anchors["box.list"]?.window === window && !store.isLoading
                && media.thumbnails[BoxBrowserFixtures.items[0].id] != nil
        }
        try await BoxWindowCaptureSupport.settle(window)
        XCTAssertEqual(window.frame.width, width, accuracy: 1)
        XCTAssertEqual(window.frame.height, 903, accuracy: 1)
        XCTAssertEqual(window.toolbarStyle, .unified)
        XCTAssertEqual(window.titleVisibility, .visible)
        XCTAssertEqual(window.styleMask, mask)
        return window
    }

    private static func rootView(store: BoxBrowserStore, media: BoxBrowserMedia, probe: LayoutProbe,
                                 scheme: ColorScheme, destination: OverviewDestination) -> some View {
        MainView(settings: AppSettings(), flow: OptionFlowStore(),
            initialDestination: destination, previewHistory: [], boxProvider: store.apiProvider,
            boxStore: store, boxMedia: media, panelsModel: PanelsModel(demoMode: true, autoload: false))
            .id(destination)
            .environment(\.colorScheme, scheme).environment(\.layoutProbe, probe)
    }
}
