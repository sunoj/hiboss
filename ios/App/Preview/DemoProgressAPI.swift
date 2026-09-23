// Demo progress service for exercising the Progress tab without a server.
// Exports DemoProgressAPI; preserves fixture paging and local like behavior.
// Dependencies: HibossKit and DemoProgressFixtures.

import HibossKit

final class DemoProgressAPI: ProgressServing, @unchecked Sendable {
    private var posts = DemoProgressFixtures.posts

    func progressFeed(project: String?, limit: Int, before: ProgressCursor?) async throws -> ProgressFeedPage {
        var posts = self.posts
        if let project { posts = posts.filter { $0.project == project } }
        if let before {
            posts = posts.filter {
                $0.createdAt < before.createdAt || ($0.createdAt == before.createdAt && $0.id < before.id)
            }
        }
        let page = Array(posts.prefix(limit))
        let next = posts.count > limit ? page.last.map { ProgressCursor(createdAt: $0.createdAt, id: $0.id) } : nil
        return ProgressFeedPage(posts: page, nextCursor: next)
    }

    func progressProjects() async throws -> [ProgressProject] {
        DemoProgressFixtures.projects
    }

    func deleteProgressPost(id _: String) async throws {}

    func likeProgressPost(id: String) async throws -> ProgressLikeState {
        applyLike(id: id, liked: true)
    }

    func unlikeProgressPost(id: String) async throws -> ProgressLikeState {
        applyLike(id: id, liked: false)
    }

    private func applyLike(id: String, liked: Bool) -> ProgressLikeState {
        guard let index = posts.firstIndex(where: { $0.id == id }) else {
            return ProgressLikeState(likeCount: 0, liked: liked)
        }
        let current = posts[index]
        let count = current.liked == liked
            ? current.likeCount
            : max(0, current.likeCount + (liked ? 1 : -1))
        posts[index] = current.withLike(count: count, liked: liked)
        return ProgressLikeState(likeCount: count, liked: liked)
    }
}
