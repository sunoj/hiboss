// Logic coverage for collection scopes, likes, memberships, management and failures.
// Exercises the browser store against the synthetic Box service.

import XCTest
import HibossKit
@testable import HibossIsland

@MainActor
final class BoxCollectionTests: XCTestCase {
    func testSidebarSelectionSeparatesBoxScopesFromWorkspaceDestinations() {
        XCTAssertEqual(BoxSidebarSelection.selected(.box, scope: .all), .workspace(.box))
        XCTAssertEqual(BoxSidebarSelection.selected(.box, scope: .liked), .scope(.liked))
        XCTAssertEqual(BoxSidebarSelection.selected(.box, scope: .collection("design")),
            .scope(.collection("design")))
        XCTAssertEqual(BoxSidebarSelection.selected(.today, scope: .liked), .workspace(.today))
        XCTAssertEqual(BoxSidebarSelection.selected(.session("session"), scope: .collection("design")),
            .workspace(.session("session")))
    }

    func testRefreshCollectionsAndScopeIdentity() async {
        let api = ScriptedBoxBrowser()
        let store = BoxBrowserStore { api }
        await store.refresh()
        XCTAssertEqual(store.collections.count, 2)
        XCTAssertNil(BoxBrowserScope.all.collectionID)
        XCTAssertEqual(BoxBrowserScope.collection("design").collectionID, "design")
        store.scope = .liked
        XCTAssertEqual(store.visibleItems.count, 2)
        store.author = .all
        store.kind = .image
        XCTAssertEqual(store.visibleItems.map(\.id), ["image"])
    }

    func testToggleLikeAndFailedMutationPreservesItem() async throws {
        let api = ScriptedBoxBrowser()
        let store = BoxBrowserStore { api }
        await store.refresh()
        let image = try XCTUnwrap(store.items.first { $0.id == "image" })
        await store.toggleLike(image)
        XCTAssertFalse(try XCTUnwrap(store.items.first { $0.id == "image" }).liked)
        await api.setMutationFailure(true)
        await store.toggleLike(image)
        XCTAssertNotNil(store.actionError)
        XCTAssertFalse(try XCTUnwrap(store.items.first { $0.id == "image" }).liked)
    }

    func testCreateRenameDeleteAndCreateWithMembership() async throws {
        let api = ScriptedBoxBrowser()
        let store = BoxBrowserStore { api }
        await store.refresh()
        let item = try XCTUnwrap(store.items.first)
        let created = await store.saveCollection(name: "  New  ", item: item)
        XCTAssertTrue(created)
        XCTAssertTrue(store.collections.contains { $0.name == "New" })
        XCTAssertTrue(try XCTUnwrap(store.items.first).collectionIDs.contains("New"))
        let renamed = await store.saveCollection(name: "Renamed", id: "New")
        XCTAssertTrue(renamed)
        let collection = try XCTUnwrap(store.collections.first { $0.id == "New" })
        XCTAssertEqual(collection.name, "Renamed")
        store.scope = .collection(collection.id)
        await store.deleteCollection(collection)
        XCTAssertEqual(store.scope, .all)
        XCTAssertFalse(store.collections.contains { $0.id == "New" })
        XCTAssertEqual(store.items.count, 5)
    }

    func testRemoveMembershipReconcilesScopedSelection() async throws {
        let api = ScriptedBoxBrowser()
        let store = BoxBrowserStore { api }
        await store.refresh()
        let image = try XCTUnwrap(store.items.first { $0.id == "image" })
        store.scope = .collection("design")
        store.selection = image.id
        await store.setMembership(image, collection: "design", member: false)
        XCTAssertFalse(store.items.contains { $0.id == image.id })
        XCTAssertNil(store.selection)
    }

    func testScopesReachPagedReadsAndSearchWithExistingFilters() async throws {
        let api = ScriptedBoxBrowser()
        let store = BoxBrowserStore { api }
        store.scope = .collection("design")
        store.kind = .image
        store.project = "HiBoss"
        store.query = "preview"
        await store.refresh()
        var filters = await api.requestedFilters
        XCTAssertEqual(try XCTUnwrap(filters.last).collection, "design")
        XCTAssertEqual(try XCTUnwrap(filters.last).kind, .image)
        XCTAssertEqual(try XCTUnwrap(filters.last).project, "HiBoss")
        store.scope = .liked
        await store.refresh()
        filters = await api.requestedFilters
        XCTAssertTrue(try XCTUnwrap(filters.last).liked)
        XCTAssertNil(try XCTUnwrap(filters.last).collection)
    }

    func testManagementFailuresAndReset() async {
        let api = ScriptedBoxBrowser()
        let store = BoxBrowserStore { api }
        await store.refresh()
        await api.setMutationFailure(true)
        let saved = await store.saveCollection(name: "Failed")
        XCTAssertFalse(saved)
        await store.deleteCollection(BoxCollectionFixtures.collections[0])
        XCTAssertEqual(store.collections.count, 2)
        XCTAssertNotNil(store.actionError)
        store.reset()
        XCTAssertTrue(store.collections.isEmpty)
        XCTAssertEqual(store.scope, .all)
    }
}
