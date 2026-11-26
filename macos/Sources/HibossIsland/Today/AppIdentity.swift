// Loads the unchanged app icon for the sidebar and a one-colour template glyph for the
// menu bar, which macOS tints for light, dark and highlighted states. Each loads once.
// Exports: AppIdentity.icon and statusIcon; the packaged images also work in hosted tests.
// Dependencies: AppKit and the app resource bundle.

import AppKit

@MainActor
enum AppIdentity {
    /// Read once: the sidebar evaluates this on every main-window update.
    static let icon: NSImage = {
        guard let url = appResourceBundle.url(forResource: "AppIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return NSImage() }
        return image
    }()

    /// The island glyph from `StatusIcon.svg`, marked as a template like system menu extras.
    static let statusIcon: NSImage = {
        guard let url = appResourceBundle.url(forResource: "StatusIcon", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return NSImage() }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()

    /// Writes only what changed: each status button write costs a menu bar layout and commit.
    static func configure(_ button: NSButton, count: Int?) {
        if button.image !== statusIcon { button.image = statusIcon }
        if button.imagePosition != .imageLeading { button.imagePosition = .imageLeading }
        let title = count.map { $0 == 0 ? "" : " \($0.formatted())" } ?? ""
        if button.title != title { button.title = title }
        let label = count.map { L("HiBoss · \($0) open decisions") } ?? L("Loading")
        if button.accessibilityLabel() != label { button.setAccessibilityLabel(label) }
    }
}
