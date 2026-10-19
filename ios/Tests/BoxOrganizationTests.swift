// Exercises the complete demo/service/store organization boundary and immutable copies.
// Covers likes, rollback, combined filters, collection lifecycle and scoped pagination.
import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class BoxOrganizationTests: XCTestCase {
    func testLikeAndUnlikePreserveContentAndOriginalTimestamp() async throws {
        let api = DemoBoxAPI()
        let store = BoxStore(api: api)
        await store.refresh()
        let original = try XCTUnwrap(store.items.first { $0.id == "demo-agent-text" })
        await store.toggleLike(original)
        let liked = try XCTUnwrap(store.items.first { $0.id == original.id })
        XCTAssertTrue(liked.liked)
        XCTAssertNotNil(liked.likedAt)
        let fetched = try await api.boxItem(id: liked.id)
        XCTAssertEqual(fetched, liked)
        let repeated = try await api.setBoxItem(id: liked.id, liked: true)
        XCTAssertEqual(repeated.likedAt, liked.likedAt)
        XCTAssertEqual(liked.text, original.text)
        XCTAssertEqual(liked.addedBy, original.addedBy)
        await store.toggleLike(liked)
        let unliked = try XCTUnwrap(store.items.first { $0.id == original.id })
        XCTAssertFalse(unliked.liked)
        XCTAssertNil(unliked.likedAt)
        XCTAssertTrue(store.organizing.isEmpty)
    }

    func testFailedLikeRollsBackAndExposesInlineError() async throws {
        let api = DemoBoxAPI()
        await api.failLikesForTest()
        let store = BoxStore(api: api)
        await store.refresh()
        let original = try XCTUnwrap(store.items.first)
        await store.toggleLike(original)
        XCTAssertEqual(store.items.first, original)
        XCTAssertNotNil(store.organizationError)
        XCTAssertTrue(store.organizing.isEmpty)
    }

    func testLikedCombinesWithKindAuthorAndSearch() throws {
        let image = try XCTUnwrap(DemoBoxAPI.fixtures.first { $0.id == "demo-image" })
        XCTAssertTrue(BoxFilter.image.matches(image, search: "layout", author: .mine, liked: true))
        XCTAssertFalse(BoxFilter.text.matches(image, search: "", liked: true))
        XCTAssertFalse(BoxFilter.image.matches(image, search: "", author: .agents, liked: true))
        XCTAssertFalse(BoxFilter.image.matches(image.organized(liked: false), search: "", liked: true))
        XCTAssertFalse(BoxFilter.image.matches(image, search: "missing", liked: true))
        let copied = image.organized(collectionIDs: ["new"])
        XCTAssertEqual(copied.collectionIDs, ["new"])
        XCTAssertEqual(copied.mediaType, image.mediaType)
        XCTAssertEqual(copied.liked, image.liked)
        XCTAssertEqual(copied.note, image.note)
    }

    func testCollectionLifecycleMembershipAndServerScope() async throws {
        let api = DemoBoxAPI()
        let store = BoxStore(api: api)
        await store.refresh()
        await store.loadCollections()
        XCTAssertEqual(store.collections.count, 2)
        let saved = await store.saveCollection(name: "  New group  ")
        XCTAssertTrue(saved)
        let collection = try XCTUnwrap(store.collections.first { $0.name == "New group" })
        let original = try XCTUnwrap(store.items.first { $0.id == "demo-image" })
        await store.setMembership(original, collection: collection, member: true)
        await store.setMembership(original, collection: collection, member: true)
        XCTAssertEqual(store.collections.first { $0.id == collection.id }?.itemCount, 1)
        XCTAssertEqual(store.collections.first { $0.id == collection.id }?.coverItemID, original.id)
        let scoped = BoxStore(api: api, collectionID: collection.id)
        await scoped.refresh()
        XCTAssertEqual(scoped.items.map(\.id), [original.id])
        XCTAssertNil(scoped.nextCursor)
        let renamed = await store.saveCollection(name: "Renamed", existing: collection)
        XCTAssertTrue(renamed)
        await store.setMembership(original, collection: collection, member: false)
        XCTAssertEqual(store.collections.first { $0.id == collection.id }?.itemCount, 0)
        await store.deleteCollection(collection)
        XCTAssertFalse(store.collections.contains { $0.id == collection.id })
        XCTAssertTrue(store.items.contains { $0.id == original.id })
        XCTAssertFalse(store.items.contains { $0.collectionIDs.contains(collection.id) })
    }

    func testCollectionNamesRejectDuplicatesEmptyLongAndControlCharacters() async throws {
        let api = DemoBoxAPI()
        let store = BoxStore(api: api)
        for name in ["reading", " ", String(repeating: "x", count: 65), "Bad\nName"] {
            let saved = await store.saveCollection(name: name)
            XCTAssertFalse(saved, name)
            XCTAssertNotNil(store.organizationError)
        }
        let collections = try await api.boxCollections()
        XCTAssertEqual(collections.count, 2)
        let filtered = try await api.boxItems(filters: BoxFilters(liked: true, collection: "demo-reading"),
                                            limit: 1, cursor: nil)
        XCTAssertEqual(filtered.items.map(\.id), ["demo-text"])
        XCTAssertNil(filtered.nextCursor)
    }

    func testScopedPaginationKeepsCollectionOnEveryPage() async throws {
        let api = DemoBoxAPI()
        for index in 1...20 {
            _ = try await api.setBoxItem(id: "demo-text-\(index)", inCollection: "demo-reading", member: true)
        }
        let store = BoxStore(api: api, collectionID: "demo-reading")
        await store.refresh()
        XCTAssertEqual(store.items.count, 20)
        XCTAssertNotNil(store.nextCursor)
        await store.loadMore()
        XCTAssertEqual(store.items.count, 22)
        XCTAssertTrue(store.items.allSatisfy { $0.collectionIDs.contains("demo-reading") })
        XCTAssertNil(store.nextCursor)
    }

    func testNoteUpdateKeepsLikeAndMemberships() async throws {
        let api = DemoBoxAPI()
        let original = try XCTUnwrap(DemoBoxAPI.fixtures.first { $0.id == "demo-image" })
        let updated = try await api.patchBoxItem(id: original.id, patch: BoxPatch(note: .value("Context")))
        XCTAssertEqual(updated.liked, original.liked)
        XCTAssertEqual(updated.likedAt, original.likedAt)
        XCTAssertEqual(updated.collectionIDs, original.collectionIDs)
        XCTAssertEqual(updated.note, "Context")
    }
}

extension DemoBoxAPI {
    func failLikesForTest() { failsLikes = true }
}
