// Owns the reusable native settings window for the menu-bar-only application.
// Exports: SettingsWindowController with a reliable show method.
// Dependencies: AppKit, SwiftUI, SettingsView, AppSettings, and OptionFlowStore.

import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(settings: AppSettings, flow: OptionFlowStore) {
        let content = NSHostingView(rootView: SettingsView(settings: settings, flow: flow))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 390),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "HiBoss Island Settings"
        window.contentView = content
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}
