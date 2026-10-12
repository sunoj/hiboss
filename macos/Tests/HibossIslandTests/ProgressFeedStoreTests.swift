// Exercises timeline order, cursor paging, filter races and confirmed shared-API mutations.
// Exports: ProgressFeedStoreTests including rollback and account-reset regressions.
// Dependencies: XCTest, HibossKit, ProgressFeedStore and ScriptedProgressAPI.

import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class ProgressFeedStoreTests: XCTestCase {
    func testPagingKeepsServerOrderAndDeduplicatesBothPages() async {
        let api = ScriptedProgressAPI(pages: [
            ProgressFeedPage(posts: [.test("z"), .test("a"), .test("z")],
                nextCursor: ProgressFixtures.cursor),
            ProgressFeedPage(posts: [.test("a"), .test("m"), .test("m")])])
        let store = ProgressFeedStore { api }
        await store.refresh()
        await store.loadMore()
        await store.loadMore()
        XCTAssertEqual(store.posts.map(\.id), ["z", "a", "m"])
        XCTAssertEqual(api.reads.map(\.cursor), [nil, ProgressFixtures.cursor])
        XCTAssertNil(store.nextCursor)
    }

    func testPagingWaitsForRefreshAndUsesItsCursor() async throws {
        let api = ScriptedProgressAPI(pages: [
            ProgressFeedPage(posts: [.test("first")], nextCursor: ProgressFixtures.cursor),
            ProgressFeedPage(posts: [.test("second")])])
        api.holdsRead = true
        let store = ProgressFeedStore { api }
        let refresh = Task { await store.refresh() }
        try await waitForCondition { api.pendingRead != nil }
        let paging = Task { await store.loadMore() }
        api.holdsRead = false
        api.releaseRead()
        await refresh.value
        await paging.value
        XCTAssertEqual(store.posts.map(\.id), ["first", "second"])
        XCTAssertEqual(api.reads.map(\.cursor), [nil, ProgressFixtures.cursor])
    }

    func testFilterSupersedesInFlightPageAndPreservesRowsUntilItsResult() async throws {
        let api = ScriptedProgressAPI(pages: [
            ProgressFeedPage(posts: [.test("old")], nextCursor: ProgressFixtures.cursor),
            ProgressFeedPage(posts: [.test("stale")]), ProgressFeedPage(posts: [.test("filtered")])])
        api.projects = [
            ProgressProject(project: "repo", count: 2, lastPostAt: nil, agentId: "a"),
            ProgressProject(project: "repo", count: 3, lastPostAt: nil, agentId: "b"),
            ProgressProject(project: "empty", count: 0, lastPostAt: nil, agentId: "a")]
        let store = ProgressFeedStore { api }
        await store.refresh()
        api.holdsRead = true
        let paging = Task { await store.loadMore() }
        try await waitForCondition { api.pendingRead != nil }
        let filter = Task { await store.selectProject("repo") }
        try await waitForCondition { store.selectedProject == "repo" }
        XCTAssertEqual(store.posts.map(\.id), ["old"])
        XCTAssertEqual(store.nextCursor, ProgressFixtures.cursor)
        api.holdsRead = false
        api.releaseRead()
        await paging.value
        await filter.value
        XCTAssertEqual(store.posts.map(\.id), ["filtered"])
        XCTAssertEqual(api.reads.last, .init(project: "repo", cursor: nil))
        XCTAssertEqual(store.projects.map(\.slug), ["empty", "repo"])
        XCTAssertEqual(store.projects.map(\.count), [0, 5])
        await store.selectProject(nil)
        XCTAssertNil(api.reads.last?.project)
    }

    func testLikeIsOptimisticDeduplicatesWritesAndUsesServerCountForUnlike() async throws {
        let api = ScriptedProgressAPI()
        let store = ProgressFeedStore { api }
        await store.refresh()
        api.holdsWrite = true
        let like = Task { await store.toggleLike(id: "image") }
        try await waitForCondition { api.pendingWrite != nil }
        XCTAssertTrue(store.posts[0].liked)
        XCTAssertEqual(store.posts[0].likeCount, 4)
        await store.toggleLike(id: "image")
        XCTAssertEqual(api.writes, ["like:image"])
        api.holdsWrite = false
        api.releaseWrite()
        await like.value
        XCTAssertEqual(store.posts[0].likeCount, 7)
        await store.toggleLike(id: "image")
        XCTAssertFalse(store.posts[0].liked)
        XCTAssertEqual(store.posts[0].likeCount, 6)
        XCTAssertEqual(api.writes, ["like:image", "unlike:image"])
    }

    func testFailedLikeRollsBackAndExposesRetryFeedback() async {
        let api = ScriptedProgressAPI()
        let store = ProgressFeedStore { api }
        await store.refresh()
        let original = store.posts[0]
        api.failsWrite = true
        await store.toggleLike(id: original.id)
        XCTAssertEqual(store.posts[0], original)
        XCTAssertNotNil(store.actionErrors[original.id])
        XCTAssertTrue(store.likingIDs.isEmpty)
        api.failsWrite = false
        await store.toggleLike(id: original.id)
        XCTAssertNil(store.actionErrors[original.id])
    }

    func testDeleteWaitsForSuccessAndDoesNotResurrectOnRefresh() async throws {
        let api = ScriptedProgressAPI()
        let store = ProgressFeedStore { api }
        await store.refresh()
        api.holdsWrite = true
        let deleting = Task { await store.delete(id: "image") }
        try await waitForCondition { api.pendingWrite != nil }
        XCTAssertEqual(store.posts.count, 3)
        await store.delete(id: "image")
        XCTAssertEqual(api.writes, ["delete:image"])
        api.holdsWrite = false
        api.releaseWrite()
        await deleting.value
        await store.refresh()
        XCTAssertEqual(store.posts.map(\.id), ["video", "text"])
        XCTAssertTrue(store.deletingIDs.isEmpty)
    }

    func testFailedDeleteKeepsPostAndDisplaysError() async {
        let api = ScriptedProgressAPI()
        let store = ProgressFeedStore { api }
        await store.refresh()
        api.failsWrite = true
        await store.delete(id: "image")
        XCTAssertEqual(store.posts.count, 3)
        XCTAssertNotNil(store.actionErrors["image"])
        api.failsWrite = false
        await store.delete(id: "image")
        XCTAssertNil(store.actionErrors["image"])
        XCTAssertEqual(store.posts.count, 2)
    }

    func testReadErrorsKeepVisiblePostsAndAllowPageRetry() async {
        let api = ScriptedProgressAPI(pages: [ProgressFeedPage(posts: [.test("first")],
            nextCursor: ProgressFixtures.cursor)])
        let store = ProgressFeedStore { api }
        await store.refresh()
        api.failsRead = true
        await store.loadMore()
        XCTAssertEqual(store.posts.map(\.id), ["first"])
        XCTAssertNotNil(store.pageError)
        XCTAssertEqual(store.nextCursor, ProgressFixtures.cursor)
        api.failsRead = false
        api.pages = [ProgressFeedPage(posts: [.test("next")])]
        await store.loadMore()
        XCTAssertNil(store.pageError)
        XCTAssertEqual(store.posts.map(\.id), ["first", "next"])
        api.failsRead = true
        await store.refresh()
        XCTAssertNotNil(store.loadError)
        XCTAssertEqual(store.posts.count, 2)
    }

    func testResetDiscardsInFlightMutationAndOldAccountState() async throws {
        let api = ScriptedProgressAPI()
        let store = ProgressFeedStore { api }
        await store.refresh()
        api.holdsWrite = true
        let like = Task { await store.toggleLike(id: "image") }
        try await waitForCondition { api.pendingWrite != nil }
        store.reset()
        api.releaseWrite()
        await like.value
        XCTAssertTrue(store.posts.isEmpty)
        XCTAssertTrue(store.likingIDs.isEmpty)
        XCTAssertTrue(store.actionErrors.isEmpty)
        XCTAssertFalse(store.didLoad)
    }

    func testUnconfiguredAndEmptyStatesAreExplicit() async {
        let unconfigured = ProgressFeedStore { nil }
        await unconfigured.refresh()
        XCTAssertTrue(unconfigured.didLoad)
        XCTAssertNotNil(unconfigured.loadError)
        let api = ScriptedProgressAPI(pages: [ProgressFeedPage(posts: [])])
        let empty = ProgressFeedStore { api }
        await empty.refresh()
        XCTAssertTrue(empty.didLoad)
        XCTAssertNil(empty.loadError)
        XCTAssertTrue(empty.posts.isEmpty)
    }
}

private extension ProgressPost {
    static func test(_ id: String) -> ProgressPost { ProgressFixtures.post(id) }
}
