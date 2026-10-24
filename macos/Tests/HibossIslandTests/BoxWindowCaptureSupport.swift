// Hosts the complete main window and captures compositor pixels, including native chrome.
// Exports: BoxWindowCaptureSupport for settled Box window regression tests.
// Dependencies: AppKit, SwiftUI, XCTest and MainView's injectable Box state.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
enum BoxWindowCaptureSupport {
    static func show(store: BoxBrowserStore, media: BoxBrowserMedia,
                     scheme: ColorScheme, probe: LayoutProbe,
                     requestedSize: NSSize = NSSize(width: 1160, height: 700)) async throws -> NSWindow {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        let host = NSHostingView(rootView: MainView(settings: AppSettings(), flow: OptionFlowStore(),
            initialDestination: .box, previewHistory: [], boxProvider: store.apiProvider,
            boxStore: store, boxMedia: media, panelsModel: PanelsModel(demoMode: true, autoload: false))
            .environment(\.colorScheme, scheme).environment(\.layoutProbe, probe))
        host.sizingOptions = []
        let screen = try XCTUnwrap(NSScreen.main).visibleFrame
        let size = NSSize(width: min(requestedSize.width, screen.width - 40),
            height: min(requestedSize.height, screen.height - 100))
        let window = NSWindow(contentRect: NSRect(origin: screen.origin,
            size: NSSize(width: size.width, height: 500)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        host.appearance = window.appearance
        window.contentView = host
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        try await waitForCondition(timeout: .seconds(5)) {
            window.toolbar != nil && store.didLoad && !store.isLoading
                && store.items.filter { $0.hasImageMedia || $0.kind == .video }
                    .allSatisfy { media.thumbnail($0.id) != nil }
        }
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.size.height = min(frame.height, screen.height)
        frame.origin = NSPoint(x: screen.minX + 20, y: screen.maxY - frame.height)
        window.setFrame(frame, display: true)
        try await settle(window)
        return window
    }

    static func settle(_ window: NSWindow) async throws {
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(750))
        try await waitForCondition { ContinuousClock.now >= deadline }
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }

    static func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    static func capture(_ window: NSWindow, directory: String, name: String,
                        includeMenus: Bool = false) throws {
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let path = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png").path
        if FileManager.default.fileExists(atPath: path) { try FileManager.default.removeItem(atPath: path) }
        let screenTop = try XCTUnwrap(NSScreen.screens.first).frame.maxY
        let screen = try XCTUnwrap(window.screen)
        let rect = includeMenus ? window.frame.insetBy(dx: -250, dy: -250).intersection(screen.frame)
            : window.frame
        let region = "\(Int(rect.minX)),\(Int(screenTop - rect.maxY)),\(Int(rect.width)),\(Int(rect.height))"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-R", region, path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let image = try XCTUnwrap(NSImage(contentsOfFile: path))
        XCTAssertGreaterThanOrEqual(image.size.width, rect.width)
    }

    @discardableResult
    static func captureMenu(_ anchor: NSView, window: NSWindow,
                            directory: String?, name: String,
                            expectedTitles: [String]? = nil) async throws -> NSMenu {
        try await settle(window)
        let session = MenuCapture(window: window, directory: directory, name: name)
        NotificationCenter.default.addObserver(session, selector: #selector(MenuCapture.didBeginTracking),
            name: NSMenu.didBeginTrackingNotification, object: nil)
        defer { NotificationCenter.default.removeObserver(session) }
        let timer = Timer(timeInterval: 0.75, repeats: false) { _ in
            MainActor.assumeIsolated { session.capture() }
        }
        RunLoop.main.add(timer, forMode: .common)
        let rect = anchor.convert(anchor.bounds, to: nil)
        let point = NSPoint(x: rect.midX, y: rect.midY)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point,
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            window.sendEvent(event)
        }
        try await waitForCondition { session.finished }
        timer.invalidate()
        if let error = session.error { throw error }
        let menu = try XCTUnwrap(session.menu, "\(name): no native menu opened")
        print("\(name) menu: \(menu.items.filter { !$0.isSeparatorItem }.map(\.title))")
        print("\(name) submenus: \(menu.items.compactMap { $0.submenu?.items.map(\.title) })")
        XCTAssertEqual(menu.items.filter { !$0.isSeparatorItem }.map(\.title),
            expectedTitles ?? BoxAuthorFilter.allCases.map { L("Source:") + " " + $0.title })
        if let directory {
            XCTAssertTrue(FileManager.default.fileExists(atPath:
                URL(fileURLWithPath: directory).appendingPathComponent("\(name).png").path))
        }
        return menu
    }

    static func capturePopupMenu(_ menu: NSMenu, window: NSWindow,
                                 directory: String?, name: String) throws {
        let session = MenuCapture(window: window, directory: directory, name: name)
        session.menu = menu
        let timer = Timer(timeInterval: 0.75, repeats: false) { _ in
            MainActor.assumeIsolated { session.capture() }
        }
        RunLoop.main.add(timer, forMode: .common)
        menu.popUp(positioning: nil, at: NSPoint(x: 100, y: 100), in: window.contentView)
        timer.invalidate()
        XCTAssertTrue(session.finished)
        if let error = session.error { throw error }
    }
}

@MainActor
private final class MenuCapture: NSObject {
    var menu: NSMenu?
    let window: NSWindow
    let directory: String?
    let name: String
    var error: (any Error)?
    var finished = false

    init(window: NSWindow, directory: String?, name: String) {
        self.window = window
        self.directory = directory
        self.name = name
    }

    @objc func didBeginTracking(_ notification: Notification) {
        menu = notification.object as? NSMenu
    }

    func capture() {
        defer { finished = true }
        do {
            if let directory {
                try BoxWindowCaptureSupport.capture(window, directory: directory,
                    name: name, includeMenus: true)
            }
        }
        catch { self.error = error }
        menu?.cancelTracking()
    }
}
