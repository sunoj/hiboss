// Verifies refresh-status publications do not change the Box list's rendering inputs.
// Exports: BoxListInvalidationTests; visible rows, selection and action state still invalidate.
// Dependencies: XCTest and the browser's existing synthetic service fixtures.

import XCTest
@testable import HibossIsland

@MainActor
final class BoxListInvalidationTests: XCTestCase {
    func testRefreshStatusReusesListInputsWhileVisibleChangesInvalidate() async {
        let api = ScriptedBoxBrowser()
        let store = BoxBrowserStore { api }
        let media = BoxBrowserMedia { api }
        await store.refresh()
        let before = list(store, media)
        await api.holdNextRead()
        let refresh = Task { await store.refresh() }
        await api.waitForHeldRead()
        XCTAssertTrue(store.isLoading)
        XCTAssertEqual(list(store, media), before)
        await api.releaseRead(.init(items: store.items))
        await refresh.value
        XCTAssertEqual(list(store, media), before)
        store.selection = "image"
        XCTAssertNotEqual(list(store, media), before)
        store.selection = nil
        XCTAssertNotEqual(list(store, media, busy: ["image"]), before)
        store.items.removeAll { $0.id == "image" }
        XCTAssertNotEqual(list(store, media), before)
    }

    private func list(_ store: BoxBrowserStore, _ media: BoxBrowserMedia,
                      busy: Set<String> = []) -> BoxBrowserList {
        BoxBrowserList(store: store, media: media, busy: busy, onOpenImage: { _ in }, onPerform: { _, _ in })
    }
}
