// Verifies shared thumbnail cache boundaries and image replacement.
// Exports BoxThumbnailCacheTests; depends on XCTest and HibossKit cache types.

import XCTest
@testable import HibossKit

@MainActor
final class BoxThumbnailCacheTests: XCTestCase {
    func testEscapedIdentifiersStayInsideTheCacheAndRemoveIndependently() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = BoxThumbnailCache(directory: directory, capacity: 1024)
        await cache.store(Data([1, 2]), for: "../outside")
        await cache.store(Data([3]), for: "peer")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(Set(files), ["%2E%2E%2Foutside.jpg", "peer.jpg"])
        await cache.remove("../outside")
        let removed = await cache.data(for: "../outside")
        let peer = await cache.data(for: "peer")
        XCTAssertNil(removed)
        XCTAssertEqual(peer, Data([3]))
    }

    func testMemoryReplacementRetainsTheLatestImage() {
        let memory = BoxThumbnailMemory(costLimit: 1024)
        let first = BoxThumbnailMemory.Image()
        let second = BoxThumbnailMemory.Image()
        #if os(iOS)
        memory.set(first, for: "same")
        memory.set(second, for: "same")
        #else
        memory.set(first, cost: 4, for: "same")
        memory.set(second, cost: 4, for: "same")
        #endif
        XCTAssertTrue(memory["same"] === second)
    }
}
