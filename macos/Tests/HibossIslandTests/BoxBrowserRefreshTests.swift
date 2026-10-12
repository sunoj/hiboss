// Regression coverage for retained Box pages, selection, and atomic refresh results.
// Exports BoxBrowserRefreshTests using held reads and synthetic paginated responses.
// Dependencies: XCTest, Combine, HibossKit, and ScriptedBoxBrowser.

import Combine
import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class BoxBrowserRefreshTests: XCTestCase {
    func testRefreshKeepsLoadedPagesSelectionAndCursorUntilCompleteResult() async {
        let first = BoxBrowserFixtures.item("first", text: "Original")
        let second = BoxBrowserFixtures.item("second", createdAt: "2026-10-08T08:00:00Z")
        let api = ScriptedBoxBrowser(pages: [BoxPage(items: [first], nextCursor: "second"),
            BoxPage(items: [second], nextCursor: "third")])
        let store = BoxBrowserStore { api }
        await store.refresh()
        await store.loadMore()
        store.selection = second.id
        let before = store.items
        var updates: [[BoxItem]] = []
        let observer = store.$items.dropFirst().sink { updates.append($0) }
        defer { observer.cancel() }
        await api.holdNextRead()
        let refresh = Task { await store.refresh() }
        await api.waitForHeldRead()
        XCTAssertEqual(store.items, before)
        XCTAssertEqual(store.selection, second.id)
        XCTAssertEqual(store.nextCursor, "third", "Keep the pagination control during refresh")
        XCTAssertTrue(updates.isEmpty)
        await api.releaseRead(BoxPage(items: [BoxBrowserFixtures.item("first", text: "Updated")],
            nextCursor: "second"))
        await refresh.value
        XCTAssertEqual(store.items.map(\.id), [first.id, second.id])
        XCTAssertEqual(store.items.first?.text, "Updated")
        XCTAssertEqual(store.selectedItem, second)
        XCTAssertEqual(store.nextCursor, "third")
        XCTAssertEqual(updates.count, 1, "Publish the complete loaded range once")
        let cursors = await api.requestedCursors
        XCTAssertEqual(cursors, [nil, "second", nil, "second"])
    }

    func testRefreshRemovesSelectionOnlyWhenAbsentFromRefetchedLoadedRange() async {
        let api = ScriptedBoxBrowser(pages: [BoxPage(items: [BoxBrowserFixtures.item("first")],
            nextCursor: "second"), BoxPage(items: [BoxBrowserFixtures.item("removed")])])
        let store = BoxBrowserStore { api }
        await store.refresh()
        await store.loadMore()
        store.selection = "removed"
        await api.setPages([BoxPage(items: [BoxBrowserFixtures.item("first")], nextCursor: "second"),
            BoxPage(items: [])])
        await store.refresh()
        XCTAssertEqual(store.items.map(\.id), ["first"])
        XCTAssertNil(store.selection)
    }

    func testRefreshPublishesNothingUntilLastLoadedPageArrives() async {
        let api = ScriptedBoxBrowser(pages: [BoxPage(items: [BoxBrowserFixtures.item("first")],
            nextCursor: "second"), BoxPage(items: [BoxBrowserFixtures.item("second")])])
        let store = BoxBrowserStore { api }
        await store.refresh()
        await store.loadMore()
        store.selection = "second"
        let before = store.items
        var updates: [[BoxItem]] = []
        let observer = store.$items.dropFirst().sink { updates.append($0) }
        defer { observer.cancel() }
        await api.setPages([BoxPage(items: [BoxBrowserFixtures.item("first", text: "Updated")],
            nextCursor: "second")])
        await api.holdNextRead(cursor: "second")
        let refresh = Task { await store.refresh() }
        await api.waitForHeldRead()
        XCTAssertEqual(store.items, before)
        XCTAssertEqual(store.selection, "second")
        XCTAssertTrue(updates.isEmpty, "Do not publish intermediate pages")
        await api.releaseRead(BoxPage(items: [BoxBrowserFixtures.item("second")]))
        await refresh.value
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(store.items.first?.text, "Updated")
        XCTAssertEqual(store.selection, "second")
    }

    func testLaterPageFailureKeepsEntireCachedRangeAndRetryCanSucceed() async {
        let api = ScriptedBoxBrowser(pages: [BoxPage(items: [BoxBrowserFixtures.item("first")],
            nextCursor: "second"), BoxPage(items: [BoxBrowserFixtures.item("second")], nextCursor: "third")])
        let store = BoxBrowserStore { api }
        await store.refresh()
        await store.loadMore()
        store.selection = "second"
        let before = store.items
        await api.holdNextRead()
        await api.setReadFailure(true)
        let refresh = Task { await store.refresh() }
        await api.waitForHeldRead()
        await api.releaseRead(BoxPage(items: [BoxBrowserFixtures.item("first", text: "Updated")],
            nextCursor: "second"))
        await refresh.value
        XCTAssertEqual(store.items, before)
        XCTAssertEqual(store.selection, "second")
        XCTAssertEqual(store.nextCursor, "third")
        XCTAssertNotNil(store.error)
        XCTAssertTrue(store.hasResult)
        await api.setReadFailure(false)
        await store.refresh()
        XCTAssertNil(store.error)
        XCTAssertEqual(store.items, before)
        XCTAssertEqual(store.selection, "second")
    }

    func testFilterChangeRefetchesOnePageInsteadOfPreviousLoadedRange() async {
        let api = ScriptedBoxBrowser(pages: [BoxPage(items: [BoxBrowserFixtures.item("first")],
            nextCursor: "second"), BoxPage(items: [BoxBrowserFixtures.item("second")])])
        let store = BoxBrowserStore { api }
        await store.refresh()
        await store.loadMore()
        store.query = "reference"
        await store.refresh()
        let cursors = await api.requestedCursors
        XCTAssertEqual(cursors, [nil, "second", nil])
        XCTAssertEqual(store.items.map(\.id), ["first"])
        XCTAssertEqual(store.nextCursor, "second")
    }

    func testNewItemsCannotPushLoadedSelectionPastRefreshBoundary() async {
        let first = BoxBrowserFixtures.item("first")
        let selected = BoxBrowserFixtures.item("selected", createdAt: "2026-10-08T08:00:00Z")
        let api = ScriptedBoxBrowser(pages: [BoxPage(items: [first], nextCursor: "second"),
            BoxPage(items: [selected], nextCursor: "third")])
        let store = BoxBrowserStore { api }
        await store.refresh()
        await store.loadMore()
        store.selection = selected.id
        await api.setPages([BoxPage(items: [BoxBrowserFixtures.item("new")], nextCursor: "second"),
            BoxPage(items: [first], nextCursor: "third"),
            BoxPage(items: [selected], nextCursor: "fourth")])
        await store.refresh()
        XCTAssertEqual(Set(store.items.map(\.id)), ["new", "first", "selected"])
        XCTAssertEqual(store.selectedItem, selected)
        XCTAssertEqual(store.nextCursor, "fourth")
        let cursors = await api.requestedCursors
        XCTAssertEqual(cursors, [nil, "second", nil, "second", "third"])
    }

    func testLoadMorePressedDuringRefreshRunsAfterTheRefresh() async {
        let first = BoxBrowserFixtures.item("first", text: "Original")
        let second = BoxBrowserFixtures.item("second", createdAt: "2026-10-08T08:00:00Z")
        let api = ScriptedBoxBrowser(pages: [BoxPage(items: [first], nextCursor: "second"),
            BoxPage(items: [second], nextCursor: nil)])
        let store = BoxBrowserStore { api }
        await store.refresh()
        await api.holdNextRead()
        let refresh = Task { await store.refresh() }
        await api.waitForHeldRead()
        await store.loadMore()
        await api.releaseRead(BoxPage(items: [first], nextCursor: "second"))
        await refresh.value
        XCTAssertEqual(store.items.map(\.id), [first.id, second.id], "Honour the click made during refresh")
        let cursors = await api.requestedCursors
        XCTAssertEqual(cursors, [nil, nil, "second"])
    }
}
