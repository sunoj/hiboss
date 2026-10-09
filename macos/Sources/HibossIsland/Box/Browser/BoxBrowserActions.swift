// Native opening and copying for Box content, with injectable system actions for tests.
// Exports: BoxBrowserActions; only authenticated local media files reach the opener.
// Dependencies: AppKit, HibossKit and BoxBrowserMedia.

import AppKit
import HibossKit

@MainActor
enum BoxBrowserActions {
    static func open(
        _ item: BoxItem, media: BoxBrowserMedia,
        opener: (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) async throws -> String? {
        if item.kind == .link {
            guard let url = item.url.flatMap(URL.init(string:)),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""), opener(url) else {
                throw BoxBrowserError.cannotOpen
            }
        } else if item.hasMedia {
            guard let file = await media.load(item) else {
                throw BoxBrowserError.media(media.errors[item.id] ?? L("Couldn't open this item."))
            }
            guard opener(file) else { throw BoxBrowserError.cannotOpen }
        } else if let text = item.text { return text }
        else { throw BoxBrowserError.cannotOpen }
        return nil
    }

    static func copy(_ text: String, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}
