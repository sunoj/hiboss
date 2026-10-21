// Offline Box fixtures served through the same list, download and delete boundary as production.
// Exports DemoBoxAPI with stable recency pages and media from bundled resources.
// Dependencies: Foundation, UIKit, HibossKit and demo grid/video resources.

import Foundation
import HibossKit
import UIKit

actor DemoBoxAPI: BoxNoteServing, BoxCollectionServing {
    static let shared = DemoBoxAPI()
    var failsLikes = ProcessInfo.processInfo.environment["HIBOSS_DEMO_BOX_LIKE_FAILURE"] == "1"
    var collectionNames = ["demo-design": "Design references", "demo-reading": "Reading"]
    var items = DemoBoxAPI.fixtures
    private var failedMedia: Set<String> = []
    private static let referenceText = "A saved reference file."

    static var fixtures: [BoxItem] {
        let unsupported = ProcessInfo.processInfo.environment["HIBOSS_DEMO_BOX_FILE"] == "unsupported"
        let pdf = ProcessInfo.processInfo.environment["HIBOSS_DEMO_BOX_FILE"] == "pdf"
        let imageFile = ProcessInfo.processInfo.environment["HIBOSS_DEMO_BOX_FILE"] == "image"
        let kinds: [BoxItem.Kind] = [.image, .text, .link, .video, .file]
        let titles = [
            "Layout reference", "A passage to keep", "Apple Developer", "Motion reference",
            pdf ? "Reference.pdf" : imageFile ? "Reference.png"
                : unsupported ? "Reference.hibossfixture" : "Reference.txt",
        ]
        let featured = kinds.enumerated().map { index, kind in
            let mediaType: String? = switch kind {
            case .image: "image/png"
            case .video: "video/mp4"
            case .file: pdf ? "application/pdf" : imageFile ? "image/png"
                : unsupported ? "application/octet-stream" : "text/plain"
            default: nil
            }
            return BoxItem(
                id: "demo-\(kind.rawValue)", bossID: "demo-boss", bossName: "Demo", kind: kind,
                text: titles[index], url: kind == .link ? "https://developer.apple.com" : nil,
                note: kind == .image ? "Use this layout for the next screen." : nil, project: "hiboss",
                tags: ["reference"], hasMedia: [.image, .video, .file].contains(kind),
                mediaType: mediaType,
                mediaBytes: kind == .file ? (pdf ? pdfData.count : referenceText.utf8.count) : nil,
                width: 320, height: 200, durationMs: kind == .video ? 1600 : nil,
                createdAt: Date().addingTimeInterval(Double(-60 * (index + 1)))
                    .ISO8601Format()
            )
        }
        let agentReference = BoxItem(
            id: "demo-agent-text", bossID: "demo-boss", bossName: "Demo", kind: .text,
            text: "Agent research notes", project: "hiboss",
            createdAt: Date().addingTimeInterval(-30).ISO8601Format(),
            addedBy: .agent(id: "demo-researcher", name: "Researcher")
        )
        let extras = ProcessInfo.processInfo.environment["HIBOSS_DEMO_BOX_V2"] == "1" ? v2Fixtures : []
        let organized = featured.map { item in
            item.organized(liked: item.kind == .image || item.kind == .text,
                           likedAt: item.createdAt,
                           collectionIDs: [item.kind == .text || item.kind == .link
                                           ? "demo-reading" : "demo-design"])
        }
        return [agentReference] + organized + extras + (1...20).map { index in
            BoxItem(id: "demo-text-\(index)", bossID: "demo-boss", bossName: "Demo", kind: .text,
                text: "Saved reference \(index)",
                createdAt: Date().addingTimeInterval(Double(-600 - index * 60))
                    .ISO8601Format())
        }
    }

    private static var v2Fixtures: [BoxItem] {
        (1...4).map { index -> BoxItem in
            let video = index == 4
            let author: BoxAuthor? = index == 3 ? .agent(id: "demo-researcher", name: "Researcher") : nil
            let date = Date().addingTimeInterval(Double(-120 - index)).ISO8601Format()
            return BoxItem(id: "demo-grid-\(index)", bossID: "demo-boss", bossName: "Demo",
                    kind: video ? .video : .image, text: "Visual reference \(index)",
                    note: "A saved composition for the next design.", project: "hiboss", tags: ["design"],
                    hasMedia: true, mediaType: video ? "video/mp4" : "image/png", mediaBytes: 1024,
                    width: 320, height: 200, durationMs: video ? 1600 : nil,
                    createdAt: date, addedBy: author)
        }
    }

    func boxItems(filters: BoxFilters, limit: Int, cursor: String?) async throws -> BoxPage {
        try await DemoDelay.wait("BOX")
        let filtered = items.filter {
            (filters.kind == nil || $0.kind == filters.kind) &&
                (!filters.liked || $0.liked) &&
                (filters.collection == nil || $0.collectionIDs.contains(filters.collection ?? "")) &&
                (filters.project == nil || $0.project == filters.project) &&
                (filters.boss == nil || $0.bossID == filters.boss || $0.bossName == filters.boss) &&
                (filters.since == nil || $0.createdAt >= (filters.since ?? ""))
        }
        let offset = cursor.flatMap { Int($0.replacingOccurrences(of: "demo-page-", with: "")) } ?? 0
        let page = Array(filtered.dropFirst(offset).prefix(limit))
        let next = offset + page.count
        return BoxPage(items: page, nextCursor: next < filtered.count ? "demo-page-\(next)" : nil)
    }

    func downloadBoxMedia(id: String, to destination: URL) async throws {
        try await DemoDelay.wait("BOX_MEDIA")
        if ProcessInfo.processInfo.environment["HIBOSS_DEMO_BOX_MEDIA_FAILURE"] == id,
           failedMedia.insert(id).inserted {
            throw HibossAPIError.requestFailed(status: 503, message: "Media unavailable")
        }
        guard let item = items.first(where: { $0.id == id }), item.hasMedia else {
            throw HibossAPIError.requestFailed(status: 404, message: "")
        }
        if item.mediaType == "application/pdf" {
            try Self.pdfData.write(to: destination)
            return
        }
        if item.kind == .file, item.mediaType != "image/png" {
            try Data(Self.referenceText.utf8).write(to: destination)
            return
        }
        let resource = item.kind == .video ? "demo-box-clip" : "demo-coarse-grid"
        let ext = item.kind == .video ? "mp4" : "png"
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else {
            throw HibossAPIError.invalidResponse
        }
        try FileManager.default.copyItem(at: url, to: destination)
    }

    private static var pdfData: Data {
        let bounds = CGRect(x: 0, y: 0, width: 360, height: 480)
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            for title in ["Box PDF reference", "Second reference page"] {
                context.beginPage()
                (title as NSString).draw(at: CGPoint(x: 28, y: 40), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 24), .foregroundColor: UIColor.black,
                ])
                ("A real PDF saved in Box." as NSString).draw(
                    at: CGPoint(x: 28, y: 90), withAttributes: [.font: UIFont.systemFont(ofSize: 16)])
            }
        }
    }

    func deleteBoxItem(id: String, purge _: Bool) async throws {
        items.removeAll { $0.id == id }
    }

    func patchBoxItem(id: String, patch: BoxPatch) async throws -> BoxItem {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            throw HibossAPIError.requestFailed(status: 404, message: "")
        }
        let item = items[index]
        let note: String?
        if case let .value(value) = patch.note { note = value } else { note = item.note }
        let updated = BoxItem(
            id: item.id, bossID: item.bossID, bossName: item.bossName, kind: item.kind,
            text: item.text, url: item.url, note: note, project: item.project, tags: item.tags,
            source: item.source, hasMedia: item.hasMedia, mediaType: item.mediaType,
            mediaBytes: item.mediaBytes, width: item.width, height: item.height,
            durationMs: item.durationMs, createdAt: item.createdAt, addedBy: item.addedBy,
            liked: item.liked, likedAt: item.likedAt, collectionIDs: item.collectionIDs)
        items[index] = updated
        return updated
    }
}
