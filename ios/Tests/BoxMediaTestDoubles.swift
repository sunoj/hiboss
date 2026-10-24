// Test doubles for Box media: a controllable clock, a fake BoxThumbnailServing that records
// requests, download paths and PUTs, and item/store factories with an isolated backfill session.
// Dependencies: XCTest, HibossKit, UIKit and the HiBoss Box media store.

import HibossKit
import UIKit
import XCTest
@testable import HiBoss

final class TestClock: @unchecked Sendable {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
}

@MainActor
enum BoxMediaFixture {
    static func image(_ index: Int, thumbnail: Bool = false) -> BoxItem {
        BoxItem(id: "image-\(index)", bossID: "boss", bossName: "Owner", kind: .image, hasMedia: true,
                mediaType: "image/png", createdAt: "2026-10-07T00:00:00Z", hasThumbnail: thumbnail)
    }

    /// A store with its own backfill session, so one test's 405 cannot leak into another.
    static func store(_ api: ThumbnailBoxAPI, cache: BoxThumbnailCache? = nil, concurrency: Int = 4,
                      memory: BoxThumbnailMemory = BoxThumbnailMemory(),
                      backfill: BoxBackfillSession = BoxBackfillSession(),
                      now: @escaping () -> Date = { Date() }) -> BoxMediaStore {
        BoxMediaStore(api: api, cache: cache, concurrency: concurrency, memory: memory,
                      backfill: backfill, now: now)
    }

    /// Polls the main actor until `condition` holds or `seconds` pass.
    static func eventually(_ seconds: Double = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return true
    }
}

actor ThumbnailBoxAPI: BoxThumbnailServing {
    static let original = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 500),
        format: { let format = UIGraphicsImageRendererFormat(); format.scale = 2; return format }())
        .image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1000, height: 500))
        }.pngData() ?? Data()
    private var failures: Int
    private var putStatuses: [Int?]
    private let delay: UInt64
    private var active = 0
    private(set) var peak = 0
    private(set) var requests: [String] = []
    private(set) var puts: [Data] = []
    private(set) var destinations: [URL] = []

    /// `putStatuses` answer PUTs in order (nil is success); the last one repeats.
    init(failures: Int = 0, putStatuses: [Int?] = [nil], delay: UInt64 = 30_000_000) {
        self.failures = failures
        self.putStatuses = putStatuses
        self.delay = delay
    }

    init(failures: Int = 0, putStatus: Int?) {
        self.init(failures: failures, putStatuses: [putStatus])
    }

    func setFailures(_ count: Int) { failures = count }

    func boxItems(filters _: BoxFilters, limit _: Int, cursor _: String?) async throws -> BoxPage {
        BoxPage(items: [])
    }

    func downloadBoxMedia(id: String, to destination: URL) async throws {
        destinations.append(destination)
        try await serve("media:\(id)")
        try Self.original.write(to: destination)
    }

    func downloadBoxThumbnail(id: String) async throws -> Data {
        try await serve("thumb:\(id)")
        return try XCTUnwrap(UIImage(data: Self.original)?.jpegData(compressionQuality: 0.5))
    }

    func uploadBoxThumbnail(id: String, data: Data, contentType _: String) async throws -> BoxItem {
        requests.append("put:\(id)")
        puts.append(data)
        let status = putStatuses.count > 1 ? putStatuses.removeFirst() : putStatuses.first ?? nil
        if let status { throw HibossAPIError.requestFailed(status: status, message: "") }
        return BoxItem(id: id, bossID: "boss", bossName: "Owner", kind: .image, createdAt: "c",
                       hasThumbnail: true)
    }

    func deleteBoxItem(id _: String, purge _: Bool) async throws {}

    private func serve(_ request: String) async throws {
        requests.append(request)
        active += 1
        peak = max(peak, active)
        defer { active -= 1 }
        try await Task.sleep(nanoseconds: delay)
        if failures > 0 {
            failures -= 1
            throw HibossAPIError.requestFailed(status: 503, message: "unavailable")
        }
    }
}
