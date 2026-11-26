// Verifies that a visible Progress timeline follows new posts without the manual refresh.
// Exports: ProgressFollowTests for newest-page merging, failure handling and follow cadence.
// Dependencies: XCTest, HibossKit, ProgressFeedStore and ScriptedProgressAPI.

import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class ProgressFollowTests: XCTestCase {
    private let older = ProgressCursor(createdAt: "2026-10-09T05:00:00Z", id: "b")
    private let newest = ProgressCursor(createdAt: "2026-10-11T05:00:00Z", id: "e")

    func testFollowPrependsNewPostsAndKeepsOlderLoadedPages() async {
        let api = ScriptedProgressAPI(pages: [
            ProgressFeedPage(posts: [ProgressFixtures.post("c"), ProgressFixtures.post("b")], nextCursor: older),
            ProgressFeedPage(posts: [ProgressFixtures.post("a")]),
            ProgressFeedPage(posts: [ProgressFixtures.post("d"), ProgressFixtures.post("c"), ProgressFixtures.post("b")], nextCursor: older)])
        api.projects = [ProgressProject(project: "hiboss", count: 3, lastPostAt: nil, agentId: "agent")]
        let store = ProgressFeedStore { api }
        await store.refresh()
        await store.loadMore()
        await store.pollLatest()
        XCTAssertEqual(store.posts.map(\.id), ["d", "c", "b", "a"])
        XCTAssertNil(store.nextCursor, "The loaded older page already reached the end")
        XCTAssertEqual(api.reads.map(\.cursor), [nil, older, nil])
        XCTAssertEqual(api.projectReads, 1, "A follow of known projects never reads the project list")
    }

    func testFollowWithoutOverlapRestartsFromNewestPage() async {
        let api = ScriptedProgressAPI(pages: [
            ProgressFeedPage(posts: [ProgressFixtures.post("b"), ProgressFixtures.post("a")]),
            ProgressFeedPage(posts: [ProgressFixtures.post("e"), ProgressFixtures.post("d")], nextCursor: newest)])
        let store = ProgressFeedStore { api }
        await store.refresh()
        await store.pollLatest()
        XCTAssertEqual(store.posts.map(\.id), ["e", "d"])
        XCTAssertEqual(store.nextCursor, newest)
    }

    func testFollowFailureKeepsTimelineWithoutError() async {
        let api = ScriptedProgressAPI(pages: [ProgressFeedPage(posts: [ProgressFixtures.post("a")])])
        let store = ProgressFeedStore { api }
        await store.refresh()
        api.failsRead = true
        await store.pollLatest()
        XCTAssertEqual(store.posts.map(\.id), ["a"])
        XCTAssertNil(store.loadError)
    }

    func testFollowReadsProjectsOnlyForAnUnknownProject() async {
        let fresh = ProgressPost(id: "n", project: "new-repo", agentId: "agent", agentName: "Builder",
            body: "Shipped n", createdAt: "2026-10-11T05:00:00Z")
        let api = ScriptedProgressAPI(pages: [
            ProgressFeedPage(posts: [ProgressFixtures.post("a")]), ProgressFeedPage(posts: [fresh, ProgressFixtures.post("a")])])
        api.projects = [ProgressProject(project: "hiboss", count: 1, lastPostAt: nil, agentId: "agent")]
        let store = ProgressFeedStore { api }
        await store.refresh()
        api.projects.append(ProgressProject(project: "new-repo", count: 1, lastPostAt: nil, agentId: "agent"))
        await store.pollLatest()
        XCTAssertEqual(api.projectReads, 2)
        XCTAssertEqual(store.projects.map(\.slug), ["hiboss", "new-repo"])
    }

    func testFollowWaitsForTheIntervalEvenWhenReadsFail() async throws {
        let api = ScriptedProgressAPI(pages: [ProgressFeedPage(posts: [ProgressFixtures.post("a")])])
        let store = ProgressFeedStore { api }
        await store.refresh()
        api.failsRead = true
        let follow = Task { await store.follow(every: 0.2) }
        defer { follow.cancel() }
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertTrue((3...5).contains(api.reads.count), "Expected 2-4 follows, read \(api.reads.count)")
        XCTAssertTrue(api.reads.allSatisfy { $0.cursor == nil })
    }
}
