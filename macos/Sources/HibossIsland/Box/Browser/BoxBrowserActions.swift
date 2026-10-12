// Native opening and copying for Box content, with injectable system actions for tests.
// Exports: BoxBrowserActions; only authenticated local media files reach the opener.
// Dependencies: AppKit, HibossKit and BoxBrowserMedia.

import AppKit
import HibossKit
import SwiftUI

enum BoxPaneAction: CaseIterable {
    case quickLook, open, copy, share, editNote, delete
    var title: String {
        switch self {
        case .quickLook: L("Quick Look")
        case .open: L("Open")
        case .copy: L("Copy")
        case .share: L("Share…")
        case .editNote: L("Edit note…")
        case .delete: L("Delete…")
        }
    }
    static func available(for item: BoxItem) -> [Self] {
        allCases.filter { $0 != .open || item.kind == .link || item.hasMedia }
    }
}

struct BoxPaneActions: View {
    let item: BoxItem
    let busy: Bool
    let perform: (BoxPaneAction) -> Void
    var actions: [BoxPaneAction] = BoxPaneAction.allCases

    var body: some View {
        ForEach(actions.filter { BoxPaneAction.available(for: item).contains($0) }, id: \.self) { action in
            Button(action.title, role: action == .delete ? .destructive : nil) { perform(action) }
                .disabled(busy)
                .accessibilityIdentifier("box.action.\(String(describing: action))")
        }
    }
}

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

    static func copy(_ item: BoxItem, media: BoxBrowserMedia) async throws {
        if item.hasMedia {
            let url = try await previewURL(item, media: media)
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.writeObjects([url as NSURL]) else {
                throw BoxBrowserError.cannotOpen
            }
        } else if !copy(item.url ?? item.text ?? "") { throw BoxBrowserError.cannotOpen }
    }

    static func previewURL(_ item: BoxItem, media: BoxBrowserMedia) async throws -> URL {
        if item.hasMedia {
            guard let file = await media.load(item) else {
                throw BoxBrowserError.media(media.errors[item.id] ?? L("Couldn't open this item."))
            }
            return file
        }
        return try media.referenceFile(item)
    }

    static func share(_ item: BoxItem, media: BoxBrowserMedia) async throws {
        let value: Any
        if item.hasMedia { value = try await previewURL(item, media: media) }
        else if item.kind == .link, let url = item.url.flatMap(URL.init(string:)) { value = url }
        else { value = item.text ?? "" }
        guard let view = NSApp.keyWindow?.contentView else { throw BoxBrowserError.cannotOpen }
        NSSharingServicePicker(items: [value]).show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
    }
}
