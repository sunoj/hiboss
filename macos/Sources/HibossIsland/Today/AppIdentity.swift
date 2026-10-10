// Loads the unchanged app icon for the sidebar and a one-colour template glyph for the
// menu bar, which macOS tints for light, dark and highlighted states.
// Exports: AppIdentity.icon and statusIcon; the packaged images also work in hosted tests.
// Dependencies: AppKit and the app resource bundle.

import AppKit

@MainActor
enum AppIdentity {
    static var icon: NSImage {
        guard let url = appResourceBundle.url(forResource: "AppIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return NSImage() }
        return image
    }

    /// The island glyph from `StatusIcon.svg`, marked as a template like system menu extras.
    static var statusIcon: NSImage {
        guard let url = appResourceBundle.url(forResource: "StatusIcon", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return NSImage() }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }

    static func configure(_ button: NSButton, count: Int?) {
        button.image = statusIcon
        button.imagePosition = .imageLeading
        button.title = count.map { $0 == 0 ? "" : " \($0.formatted())" } ?? ""
        button.setAccessibilityLabel(count.map { L("HiBoss · \($0) open decisions") } ?? L("Loading"))
    }
}
