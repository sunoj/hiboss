// Successful empty results remain distinct from first-read failures across shared list stores.
// Exports LoadedSnapshotTests; verifies loaded latches before the shared empty-state gate.
// Dependencies: XCTest, HibossKit, InboxStore, and ProgressFeedStore.

import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class LoadedSnapshotTests: XCTestCase {
    func testFailedFirstHistoryReadDoesNotClaimAnEmptyResult() async {
        let api = ControlledInputAPI()
        await api.failHistory()
        let store = InboxStore(decisionAlertsEnabled: false)
        store.api = api
        defer { store.stop() }
        await store.refresh()
        XCTAssertFalse(store.didLoad)
        XCTAssertNotNil(store.loadError)
    }

    func testFailedFirstProgressReadDoesNotClaimAnEmptyResult() async {
        let store = ProgressFeedStore()
        store.start(api: FailingFeedRead())
        await store.refresh()
        XCTAssertFalse(store.didLoad)
        XCTAssertNotNil(store.loadError)
    }
}

private actor FailingFeedRead: ProgressServing {
    func progressFeed(project: String?, limit: Int, before: ProgressCursor?) async throws
        -> ProgressFeedPage {
        throw URLError(.notConnectedToInternet)
    }
    func progressProjects() async throws -> [ProgressProject] { [] }
    func deleteProgressPost(id: String) async throws {}
    func likeProgressPost(id: String) async throws -> ProgressLikeState {
        ProgressLikeState(likeCount: 0, liked: false)
    }
    func unlikeProgressPost(id: String) async throws -> ProgressLikeState {
        ProgressLikeState(likeCount: 0, liked: false)
    }
}
