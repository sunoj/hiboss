// Progress feed store tests for cursor pagination serialization.
// Exports: ProgressFeedStoreTests covering refresh/loadMore ordering.
// Dependencies: XCTest, HiBoss app target, HibossKit ProgressServing.

import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class ProgressFeedStoreTests: XCTestCase {
    func testLoadMoreWaitsForRefreshAndKeepsTheReturnedCursor() async {
        let api = DelayedProgressAPI()
        let store = ProgressFeedStore()
        store.start(api: api)

        let refresh = Task { @MainActor in await store.refresh() }
        try? await Task.sleep(for: .milliseconds(10))
        let loadMore = Task { @MainActor in await store.loadMore() }
        await refresh.value
        await loadMore.value

        XCTAssertEqual(store.posts.map(\.id), ["first", "second"])
        XCTAssertEqual(api.beforeCursors, [nil, ProgressCursor(createdAt: "2026-08-14T09:00:00Z", id: "first")])
    }
}

private final class DelayedProgressAPI: ProgressServing, @unchecked Sendable {
    var beforeCursors: [ProgressCursor?] = []

    func progressFeed(project _: String?, limit _: Int, before: ProgressCursor?) async throws -> ProgressFeedPage {
        beforeCursors.append(before)
        if before == nil {
            try await Task.sleep(for: .milliseconds(40))
            return ProgressFeedPage(
                posts: [post(id: "first", body: "first")],
                nextCursor: ProgressCursor(createdAt: "2026-08-14T09:00:00Z", id: "first")
            )
        }
        return ProgressFeedPage(posts: [post(id: "second", body: "second")])
    }

    func progressProjects() async throws -> [ProgressProject] { [] }

    func deleteProgressPost(id _: String) async throws {}

    private func post(id: String, body: String) -> ProgressPost {
        ProgressPost(id: id, project: "hiboss", agentId: "agent", agentName: "cli", body: body, createdAt: "2026-08-14T09:00:00Z")
    }
}
