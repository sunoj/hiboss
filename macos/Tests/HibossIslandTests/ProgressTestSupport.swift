// Deterministic shared-API fixture for progress store and hosted timeline tests.
// Exports: ScriptedProgressAPI and ProgressFixtures with controllable read/write completion.
// Dependencies: HibossKit, Foundation and test-only checked continuations.

import Foundation
import HibossKit

@MainActor
final class ScriptedProgressAPI: ProgressServing {
    struct Read: Equatable {
        let project: String?
        let cursor: ProgressCursor?
    }
    var pages: [ProgressFeedPage]
    var projects: [ProgressProject] = []
    var reads: [Read] = []
    var writes: [String] = []
    var failsRead = false
    var failsWrite = false
    var holdsRead = false
    var holdsWrite = false
    var pendingRead: CheckedContinuation<Void, Never>?
    var pendingWrite: CheckedContinuation<Void, Never>?

    init(pages: [ProgressFeedPage] = [ProgressFeedPage(posts: ProgressFixtures.posts())]) {
        self.pages = pages
    }

    func progressFeed(project: String?, limit: Int, before: ProgressCursor?) async throws
        -> ProgressFeedPage {
        reads.append(Read(project: project, cursor: before))
        let page = pages.count > 1 ? pages.removeFirst() : pages.first ?? ProgressFeedPage(posts: [])
        if holdsRead { await withCheckedContinuation { pendingRead = $0 } }
        if failsRead { throw HibossAPIError.invalidResponse }
        return page
    }

    func progressProjects() async throws -> [ProgressProject] { projects }

    func deleteProgressPost(id: String) async throws { try await write("delete:\(id)") }

    func likeProgressPost(id: String) async throws -> ProgressLikeState {
        try await write("like:\(id)")
        return ProgressLikeState(likeCount: 7, liked: true)
    }

    func unlikeProgressPost(id: String) async throws -> ProgressLikeState {
        try await write("unlike:\(id)")
        return ProgressLikeState(likeCount: 6, liked: false)
    }

    private func write(_ call: String) async throws {
        writes.append(call)
        if holdsWrite { await withCheckedContinuation { pendingWrite = $0 } }
        if failsWrite { throw HibossAPIError.invalidResponse }
    }

    func releaseRead() {
        pendingRead?.resume()
        pendingRead = nil
    }

    func releaseWrite() {
        pendingWrite?.resume()
        pendingWrite = nil
    }
}

enum ProgressFixtures {
    static let cursor = ProgressCursor(createdAt: "2026-10-10T05:00:00Z", id: "image")

    static func post(_ id: String) -> ProgressPost {
        ProgressPost(id: id, project: "hiboss", agentId: "agent", agentName: "Builder",
            body: "Shipped \(id)", createdAt: "2026-10-10T05:00:00Z")
    }

    static func posts(baseURL: String? = nil) -> [ProgressPost] {
        let image = baseURL.map { [ProgressMedia(url: "\($0)/ship.png", kind: .image,
            contentType: "image/png", size: 100, width: 480, height: 320, alt: "Release preview")] } ?? []
        let video = baseURL.map { [ProgressMedia(url: "\($0)/preview.mp4", kind: .video,
            contentType: "video/mp4", size: 100, posterUrl: "\($0)/hold.png",
            alt: "Navigation walkthrough")] }
            ?? []
        return [
            ProgressPost(id: "image", project: "hiboss", agentId: "builder", agentName: "Builder",
                body: "The new progress timeline is ready.", media: image, tags: ["macOS", "release"],
                createdAt: AttentionTestSupport.iso(.now.addingTimeInterval(-120)), likeCount: 3),
            ProgressPost(id: "video", project: "hiboss", agentId: "designer", agentName: "Designer",
                body: "A short walkthrough of the native navigation.", media: video, tags: ["demo"],
                createdAt: AttentionTestSupport.iso(.now.addingTimeInterval(-3600)),
                likeCount: 1, liked: true),
            ProgressPost(id: "text", project: "tooling", agentId: "tester", agentName: "Tester",
                body: "Paging and project filters now preserve the server's order.", tags: ["tests"],
                createdAt: AttentionTestSupport.iso(.now.addingTimeInterval(-7200)))
        ]
    }
}
