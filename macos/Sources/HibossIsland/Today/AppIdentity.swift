// Loads the unchanged app icon for the sidebar and native menu-bar item.
// Exports: AppIdentity.icon; the packaged image also works in hosted tests.
// Dependencies: AppKit and the app resource bundle.

import AppKit

@MainActor
enum AppIdentity {
    static var icon: NSImage {
        guard let url = appResourceBundle.url(forResource: "AppIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return NSImage() }
        return image
    }

    static func configure(_ button: NSButton, count: Int?) {
        let image = icon
        image.size = NSSize(width: 18, height: 18)
        button.image = image
        button.imagePosition = .imageLeading
        button.title = count.map { $0 == 0 ? "" : " \($0.formatted())" } ?? ""
        button.setAccessibilityLabel(count.map { L("HiBoss · \($0) open decisions") } ?? L("Loading"))
    }
}
