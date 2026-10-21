// The signed-out main window offers Pair with Code in place and opens the redeem sheet.
// Exports: FirstRunWindowTests; HIBOSS_FIRST_RUN_SHOTS writes light/dark full-window captures.
// Dependencies: AppKit, SwiftUI, XCTest, MainView, FirstRunGate, and BoxWindowCaptureSupport.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class FirstRunWindowTests: XCTestCase {
    func testSignedOutWindowPairsWithCodeInPlace() async throws {
        let suite = "FirstRunWindowTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults, keychain: FirstRunTokens())
        await settings.loadToken()
        XCTAssertTrue(settings.needsSignIn)
        let directory = ProcessInfo.processInfo.environment["HIBOSS_FIRST_RUN_SHOTS"]
        for scheme in [ColorScheme.light, .dark] {
            let probe = LayoutProbe()
            let window = try await show(settings: settings, scheme: scheme, probe: probe)
            defer { window.close() }
            let name = scheme == .light ? "light" : "dark"
            if let directory { try BoxWindowCaptureSupport.capture(window, directory: directory, name: "first-run-\(name)") }
            XCTAssertNotNil(probe.anchors["firstRun.otherWays"])
            try click(try XCTUnwrap(probe.anchors["firstRun.pairWithCode"]), in: window)
            try await waitForCondition(timeout: .seconds(5)) { window.attachedSheet != nil }
            let sheet = try XCTUnwrap(window.attachedSheet)
            try await BoxWindowCaptureSupport.settle(sheet)
            if let directory {
                try BoxWindowCaptureSupport.capture(window, directory: directory, name: "first-run-pair-\(name)")
            }
            window.endSheet(sheet)
        }
    }

    private func click(_ anchor: NSView, in window: NSWindow) throws {
        let rect = anchor.convert(anchor.bounds, to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            window.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(with: type, location: NSPoint(x: rect.midX, y: rect.midY),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)))
        }
    }

    private func show(settings: AppSettings, scheme: ColorScheme, probe: LayoutProbe) async throws -> NSWindow {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        let host = NSHostingView(rootView: MainView(settings: settings, flow: OptionFlowStore(),
            previewHistory: nil, panelsModel: PanelsModel(demoMode: false, autoload: false))
            .environment(\.colorScheme, scheme).environment(\.layoutProbe, probe))
        host.sizingOptions = []
        let screen = try XCTUnwrap(NSScreen.main).visibleFrame
        let window = NSWindow(contentRect: NSRect(x: screen.minX + 20, y: screen.maxY - 740, width: 1100, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        host.appearance = window.appearance
        window.contentView = host
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        try await waitForCondition(timeout: .seconds(5)) { probe.anchors["firstRun.pairWithCode"] != nil }
        try await BoxWindowCaptureSupport.settle(window)
        return window
    }
}

private struct FirstRunTokens: TokenStoring {
    func read() throws -> String? { nil }
    func write(_ token: String) throws {}
}
