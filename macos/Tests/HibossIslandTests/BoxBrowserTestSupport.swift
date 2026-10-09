// Synthetic reference items and controllable Box service for browser and snapshot tests.
// Exports: BoxBrowserFixtures and ScriptedBoxBrowser; no live credentials or services.
// Dependencies: AppKit, HibossKit and the macOS BoxBrowsing boundary.

import AppKit
import HibossKit
@testable import HibossIsland

enum BoxBrowserFixtures {
    static let items: [BoxItem] = [
        item("image", kind: .image, text: "Navigation preview.png",
            note: "Use this layout for the next pass.",
            hasMedia: true, mediaType: "image/png", author: .agent(id: "designer", name: "Design Agent")),
        item("link", kind: .link, text: "SwiftUI documentation", url: "https://developer.apple.com/swiftui/",
            note: "Native controls and accessibility."),
        item("text", text: "Keep the main action visible at narrow window widths.",
            author: .agent(id: "reviewer", name: nil)),
        item("file", kind: .file, text: "review-notes.pdf", note: "Detailed review notes.",
            hasMedia: true, mediaType: "application/pdf"),
        item("video", kind: .video, text: "walkthrough.mp4", hasMedia: true, mediaType: "video/mp4")
    ]

    static func item(
        _ id: String, kind: BoxItem.Kind = .text, text: String? = nil, url: String? = nil,
        note: String? = nil, hasMedia: Bool = false, mediaType: String? = nil,
        author: BoxAuthor? = nil, createdAt: String = "2026-10-09T08:30:00Z"
    ) -> BoxItem {
        BoxItem(id: id, bossID: "test-boss", bossName: "Test Boss", kind: kind, text: text, url: url,
            note: note, project: "HiBoss", tags: ["reference", "design"], source: .macDrop,
            hasMedia: hasMedia, mediaType: mediaType, createdAt: createdAt, addedBy: author)
    }

    @MainActor static func imageData() -> Data {
        let image = NSImage(size: NSSize(width: 120, height: 80))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 120, height: 80).fill()
        NSColor.systemYellow.setFill()
        NSRect(x: 16, y: 16, width: 88, height: 16).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return Data() }
        return png
    }
}

actor ScriptedBoxBrowser: BoxBrowsing {
    var pages: [BoxPage]
    var failRead = false
    var failDelete = false
    var heldRead: CheckedContinuation<BoxPage, any Error>?
    var readObserver: CheckedContinuation<Void, Never>?
    var holdsNextRead = false
    private(set) var deleted: [String] = []
    private(set) var downloads = 0
    private let media: Data

    init(pages: [BoxPage] = [BoxPage(items: BoxBrowserFixtures.items)], media: Data = Data()) {
        self.pages = pages
        self.media = media
    }

    func setReadFailure(_ fails: Bool) { failRead = fails }
    func setDeleteFailure(_ fails: Bool) { failDelete = fails }
    func holdNextRead() { holdsNextRead = true }
    func waitForHeldRead() async {
        if heldRead != nil { return }
        await withCheckedContinuation { readObserver = $0 }
    }
    func releaseRead(_ page: BoxPage) {
        heldRead?.resume(returning: page)
        heldRead = nil
    }

    func boxItems(filters: BoxFilters, limit: Int, cursor: String?) async throws -> BoxPage {
        if holdsNextRead {
            holdsNextRead = false
            return try await withCheckedThrowingContinuation {
                heldRead = $0
                readObserver?.resume()
                readObserver = nil
            }
        }
        if failRead { throw TestError.rejected }
        return pages[min(cursor == nil ? 0 : 1, pages.count - 1)]
    }

    func searchBoxItems(
        query: String, filters: BoxFilters, limit: Int, cursor: String?
    ) async throws -> BoxPage {
        try await boxItems(filters: filters, limit: limit, cursor: cursor)
    }

    func downloadBoxMedia(id: String, to destination: URL) async throws {
        downloads += 1
        try media.write(to: destination)
    }

    func deleteBoxItem(id: String, purge: Bool) async throws {
        if failDelete { throw TestError.rejected }
        deleted.append(id)
    }
}
