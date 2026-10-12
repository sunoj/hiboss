// Keeps submission feedback independent of project-filter read generations.
// Exports ProgressRefreshMutationTests for a held like followed by a filter refresh.
// Dependencies: XCTest, ProgressFeedStore, and the local progress read/write gates.

import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class ProgressRefreshMutationTests: XCTestCase {
    func testFilterKeepsTheSubmittingLikeUntilItsOwnResponseArrives() async throws {
        let api = ScriptedProgressAPI()
        let store = ProgressFeedStore { api }
        await store.refresh()
        api.holdsWrite = true
        let like = Task { await store.toggleLike(id: "image") }
        try await waitForCondition { api.pendingWrite != nil }
        let cached = store.posts
        let filter = Task { await store.selectProject("hiboss") }
        try await waitForCondition { store.selectedProject == "hiboss" }
        XCTAssertEqual(store.posts, cached)
        XCTAssertEqual(store.likingIDs, ["image"])
        XCTAssertEqual(api.writes, ["like:image"])
        api.holdsRead = true
        api.holdsWrite = false
        api.releaseWrite()
        await like.value
        try await waitForCondition { api.pendingRead != nil }
        XCTAssertTrue(store.likingIDs.isEmpty)
        XCTAssertEqual(store.posts.first?.likeCount, 7)
        api.holdsRead = false
        api.releaseRead()
        await filter.value
    }
}
