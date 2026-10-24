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
            hasMedia: true, mediaType: "image/png", mediaBytes: 1_200_000,
            width: 1600, height: 900, author: .agent(id: "designer", name: "Design Agent")),
        item("link", kind: .link, text: "SwiftUI documentation", url: "https://developer.apple.com/swiftui/",
            note: "Native controls and accessibility."),
        item("text", text: "Keep the main action visible at narrow window widths.",
            author: .agent(id: "reviewer", name: nil)),
        item("file", kind: .file, text: "review-notes.pdf", note: "Detailed review notes.",
            hasMedia: true, mediaType: "application/pdf", mediaBytes: 240_000),
        item("video", kind: .video, text: "walkthrough.mp4", hasMedia: true,
            mediaType: "video/mp4", mediaBytes: 8_400_000, durationMs: 12_000)
    ]

    static func item(
        _ id: String, kind: BoxItem.Kind = .text, text: String? = nil, url: String? = nil,
        note: String? = nil, hasMedia: Bool = false, mediaType: String? = nil,
        mediaBytes: Int? = nil, width: Int? = nil, height: Int? = nil,
        author: BoxAuthor? = nil, createdAt: String = "2026-10-09T08:30:00Z", durationMs: Int? = nil
    ) -> BoxItem {
        BoxItem(id: id, bossID: "test-boss", bossName: "Test Boss", kind: kind, text: text, url: url,
            note: note, project: "HiBoss", tags: ["reference", "design"], source: .macDrop,
            hasMedia: hasMedia, mediaType: mediaType, mediaBytes: mediaBytes, width: width,
            height: height, durationMs: durationMs,
            createdAt: createdAt, addedBy: author, liked: id == "image" || id == "link",
            collectionIDs: id == "image" ? ["design"] : [])
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
    var collections = BoxCollectionFixtures.collections
    var failMutation = false
    var pages: [BoxPage]
    var failRead = false
    var failDelete = false
    var heldRead: CheckedContinuation<BoxPage, any Error>?
    var readObserver: CheckedContinuation<Void, Never>?
    var holdsNextRead = false
    private var heldCursor: String?
    private(set) var requestedFilters: [BoxFilters] = []
    private(set) var requestedCursors: [String?] = []
    private(set) var deleted: [String] = []
    private(set) var downloads = 0
    private(set) var downloadsByID: [String: Int] = [:]
    private(set) var storedThumbnails: [String: Data] = [:]
    private(set) var requests: [String] = []
    private(set) var peak = 0
    private(set) var putPeak = 0
    private var active = 0
    private var activePuts = 0
    private var delay: UInt64 = 0
    private var failures = 0
    private var putStatus: Int?
    private var putDelay: UInt64 = 0
    private let media: Data
    private let mediaByID: [String: Data]

    init(pages: [BoxPage] = [BoxPage(items: BoxBrowserFixtures.items)], media: Data = Data(),
         mediaByID: [String: Data] = [:]) {
        self.pages = pages
        self.media = media
        self.mediaByID = mediaByID
    }

    func setReadFailure(_ fails: Bool) { failRead = fails }
    func setDeleteFailure(_ fails: Bool) { failDelete = fails }
    func setPages(_ pages: [BoxPage]) { self.pages = pages }
    func holdNextRead(cursor: String? = nil) {
        holdsNextRead = true
        heldCursor = cursor
    }
    func waitForHeldRead() async {
        if heldRead != nil { return }
        await withCheckedContinuation { readObserver = $0 }
    }
    func releaseRead(_ page: BoxPage) {
        heldRead?.resume(returning: page)
        heldRead = nil
    }

    func boxItems(filters: BoxFilters, limit: Int, cursor: String?) async throws -> BoxPage {
        requestedCursors.append(cursor)
        requestedFilters.append(filters)
        if holdsNextRead && (heldCursor == nil || heldCursor == cursor) {
            holdsNextRead = false
            return try await withCheckedThrowingContinuation {
                heldRead = $0
                readObserver?.resume()
                readObserver = nil
            }
        }
        if failRead { throw TestError.rejected }
        let index = cursor.flatMap { cursor in pages.firstIndex { $0.nextCursor == cursor } }
            .map { $0 + 1 } ?? 0
        return pages[min(index, pages.count - 1)]
    }

    func searchBoxItems(
        query: String, filters: BoxFilters, limit: Int, cursor: String?
    ) async throws -> BoxPage {
        try await boxItems(filters: filters, limit: limit, cursor: cursor)
    }

    func downloadBoxMedia(id: String, to destination: URL) async throws {
        downloads += 1
        downloadsByID[id, default: 0] += 1
        try await serve("media:\(id)")
        try (mediaByID[id] ?? media).write(to: destination)
    }

    func storeThumbnail(_ data: Data, for id: String) { storedThumbnails[id] = data }

    func script(delay: UInt64 = 0, failures: Int = 0, putStatus: Int? = nil, putDelay: UInt64 = 0) {
        self.delay = delay
        self.failures = failures
        self.putStatus = putStatus
        self.putDelay = putDelay
    }

    /// Records the request and the concurrency peak, then fails while scripted failures remain.
    private func serve(_ request: String) async throws {
        requests.append(request)
        active += 1
        peak = max(peak, active)
        defer { active -= 1 }
        if delay > 0 { try await Task.sleep(nanoseconds: delay) }
        if failures > 0 {
            failures -= 1
            throw HibossAPIError.requestFailed(status: 503, message: "unavailable")
        }
    }

    func deleteBoxItem(id: String, purge: Bool) async throws {
        if failDelete { throw TestError.rejected }
        deleted.append(id)
    }

    func patchBoxItem(id: String, patch: BoxPatch) async throws -> BoxItem {
        let item = pages.flatMap(\.items).first { $0.id == id } ?? BoxBrowserFixtures.item(id)
        let note: String?
        if case let .value(value) = patch.note { note = value } else { note = item.note }
        return BoxItem(id: item.id, bossID: item.bossID, bossName: item.bossName, kind: item.kind,
            text: item.text, url: item.url, note: note, project: item.project, tags: item.tags,
            source: item.source, hasMedia: item.hasMedia, mediaType: item.mediaType,
            mediaBytes: item.mediaBytes, width: item.width, height: item.height,
            durationMs: item.durationMs, createdAt: item.createdAt, addedBy: item.addedBy,
            liked: item.liked, likedAt: item.likedAt, collectionIDs: item.collectionIDs,
            hasThumbnail: item.hasThumbnail)
    }

    func downloadBoxThumbnail(id: String) async throws -> Data {
        try await serve("thumb:\(id)")
        guard let data = storedThumbnails[id] else {
            throw HibossAPIError.requestFailed(status: 404, message: "")
        }
        return data
    }

    func uploadBoxThumbnail(id: String, data: Data, contentType: String) async throws -> BoxItem {
        requests.append("put:\(id)")
        activePuts += 1
        putPeak = max(putPeak, activePuts)
        defer { activePuts -= 1 }
        if putDelay > 0 { try await Task.sleep(nanoseconds: putDelay) }
        if let putStatus { throw HibossAPIError.requestFailed(status: putStatus, message: "") }
        storedThumbnails[id] = data
        return pages.flatMap(\.items).first { $0.id == id } ?? BoxBrowserFixtures.item(id)
    }
}
