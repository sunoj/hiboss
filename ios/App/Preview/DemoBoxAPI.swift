// Offline Box fixtures served through the same list, download and delete boundary as production.
// Exports DemoBoxAPI with stable recency pages and media from bundled resources.
// Dependencies: Foundation, HibossKit and demo grid/video resources.

import Foundation
import HibossKit

actor DemoBoxAPI: BoxServing {
    static let shared = DemoBoxAPI()
    private var items = DemoBoxAPI.fixtures

    static var fixtures: [BoxItem] {
        let unsupported = ProcessInfo.processInfo.environment["HIBOSS_DEMO_BOX_FILE"] == "unsupported"
        let kinds: [BoxItem.Kind] = [.image, .text, .link, .video, .file]
        let titles = [
            "Layout reference", "A passage to keep", "Apple Developer", "Motion reference",
            unsupported ? "Reference.hibossfixture" : "Reference.txt",
        ]
        let featured = kinds.enumerated().map { index, kind in
            BoxItem(
                id: "demo-\(kind.rawValue)", bossID: "demo-boss", bossName: "Demo", kind: kind,
                text: titles[index], url: kind == .link ? "https://developer.apple.com" : nil,
                note: kind == .image ? "Use this layout for the next screen." : nil, project: "hiboss",
                tags: ["reference"], hasMedia: [.image, .video, .file].contains(kind),
                mediaType: kind == .video ? "video/mp4" : kind == .file
                    ? (unsupported ? "application/octet-stream" : "text/plain") : "image/png",
                mediaBytes: kind == .file ? "A saved reference file.".utf8.count : nil,
                width: 320, height: 200, createdAt: Date().addingTimeInterval(Double(-60 * (index + 1)))
                    .ISO8601Format()
            )
        }
        return featured + (1...20).map { index in
            BoxItem(id: "demo-text-\(index)", bossID: "demo-boss", bossName: "Demo", kind: .text,
                text: "Saved reference \(index)",
                createdAt: Date().addingTimeInterval(Double(-600 - index * 60))
                    .ISO8601Format())
        }
    }

    func boxItems(filters: BoxFilters, limit: Int, cursor: String?) async throws -> BoxPage {
        try await DemoDelay.wait("BOX")
        let filtered = items.filter {
            (filters.kind == nil || $0.kind == filters.kind) &&
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
        guard let item = items.first(where: { $0.id == id }), item.hasMedia else {
            throw HibossAPIError.requestFailed(status: 404, message: "")
        }
        if item.kind == .file {
            try Data("A saved reference file.".utf8).write(to: destination)
            return
        }
        let resource = item.kind == .video ? "demo-box-clip" : "demo-coarse-grid"
        let ext = item.kind == .video ? "mp4" : "png"
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else {
            throw HibossAPIError.invalidResponse
        }
        try FileManager.default.copyItem(at: url, to: destination)
    }

    func deleteBoxItem(id: String, purge _: Bool) async throws {
        items.removeAll { $0.id == id }
    }
}
