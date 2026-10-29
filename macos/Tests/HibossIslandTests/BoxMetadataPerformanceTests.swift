// Bounds repeated row metadata work independently of native layout and desktop timing.
// Exports: BoxMetadataPerformanceTests using synthetic 500-item browser data.
// Dependencies: XCTest, Darwin's thread CPU clock and BoxItem presentation.

import Darwin
import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class BoxMetadataPerformanceTests: XCTestCase {
    func testRepeatedMetadataPassesReuseFormattedValues() {
        let items = (0..<500).map { BoxBrowserFixtures.item("metadata-\($0)", text: "Reference \($0)") }
        let now = Date(timeIntervalSince1970: 1_793_000_000)
        let expected = items.map { $0.metadata(now: now) }
        let start = mainCPU()
        for _ in 0..<10 {
            XCTAssertEqual(items.map { $0.metadata(now: now) }, expected)
        }
        let milliseconds = (mainCPU() - start) * 1_000
        XCTAssertLessThan(milliseconds, 100, "Repeated metadata CPU: \(milliseconds) ms")
    }

    func testMetadataExpiresAtDisplayedMinuteAndItemChanges() throws {
        let date = try XCTUnwrap(ISODate.parse("2026-10-29T08:00:00Z"))
        let item = BoxBrowserFixtures.item("metadata-boundaries", createdAt: "2026-10-29T08:00:00Z")
        for elapsed: TimeInterval in [0, 59, 60, 119, 120, 43_199, 43_200, 86_400] {
            let now = date.addingTimeInterval(elapsed)
            let expected = [item.kindTitle, item.sizeTitle, BoxTime.relative(item.createdAt, now: now),
                item.authorTitle, item.project].compactMap { $0 }.joined(separator: " · ")
            XCTAssertEqual(item.metadata(now: now), expected, "Elapsed: \(elapsed)")
        }
        let changed = BoxBrowserFixtures.item(item.id, kind: .file, text: "Updated.pdf",
            mediaBytes: 42_000, author: .agent(id: "a", name: "Reviewer"), createdAt: item.createdAt)
        XCTAssertNotEqual(changed.metadata(now: date), item.metadata(now: date))
    }

    func testMetadataBuildsOnceUntilItsDisplayedMinuteChanges() throws {
        let date = try XCTUnwrap(ISODate.parse("2026-10-29T08:00:00Z"))
        let item = BoxBrowserFixtures.item("metadata-build-count", createdAt: "2026-10-29T08:00:00Z")
        var builds = 0
        for offset in 0..<500 {
            let value = BoxMetadataCache.value(for: item, now: date.addingTimeInterval(Double(offset) / 10)) {
                builds += 1
                return "formatted"
            }
            XCTAssertEqual(value, "formatted")
        }
        XCTAssertEqual(builds, 1)
        _ = BoxMetadataCache.value(for: item, now: date.addingTimeInterval(60)) {
            builds += 1
            return "next minute"
        }
        XCTAssertEqual(builds, 2)
    }

    func testVisibleProjectionReusesStorageAndInvalidatesForEveryLocalFilter() {
        let store = BoxBrowserStore { nil }
        store.items = BoxBrowserFixtures.items
        let first = store.visibleItems
        let second = store.visibleItems
        XCTAssertEqual(first.withUnsafeBufferPointer { $0.baseAddress },
            second.withUnsafeBufferPointer { $0.baseAddress })
        store.author = .agents
        XCTAssertEqual(store.visibleItems.map(\.id), ["image", "text"])
        store.kind = .text
        XCTAssertEqual(store.visibleItems.map(\.id), ["text"])
        store.scope = .liked
        XCTAssertTrue(store.visibleItems.isEmpty)
        store.kind = nil
        XCTAssertEqual(store.visibleItems.map(\.id), ["image"])
        store.items.removeAll { $0.id == "image" }
        XCTAssertTrue(store.visibleItems.isEmpty)
        store.reset()
        XCTAssertTrue(store.visibleItems.isEmpty)
    }

    private func mainCPU() -> Double {
        var time = timespec()
        precondition(clock_gettime(CLOCK_THREAD_CPUTIME_ID, &time) == 0)
        return Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000
    }
}
