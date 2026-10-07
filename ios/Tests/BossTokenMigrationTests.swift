// Covers every migration decision and failure before private-token deletion.
// Exports BossTokenMigrationTests with an ordered, in-memory token boundary.
// Dependencies: XCTest and HibossKit.

import HibossKit
import XCTest

final class BossTokenMigrationTests: XCTestCase {
    func testMissingOrEmptyLegacyTokenDoesNothing() throws {
        for token in [nil, ""] {
            let old = MigrationTokenStore(token)
            let shared = MigrationTokenStore(nil)
            try BossTokenMigration(legacy: old, shared: shared).migrate()
            XCTAssertEqual(old.deletes, 0)
            XCTAssertEqual(shared.writes, 0)
        }
    }

    func testExistingDifferentOrSignedOutSharedTokenIsNeverOverwritten() throws {
        for token in ["other", ""] {
            let old = MigrationTokenStore("fixture")
            let shared = MigrationTokenStore(token)
            try BossTokenMigration(legacy: old, shared: shared).migrate()
            XCTAssertEqual(shared.value, token)
            XCTAssertEqual(shared.writes, 0)
            XCTAssertEqual(old.deletes, 0)
        }
    }

    func testMigrationVerifiesBeforeDeletingAndIsIdempotent() throws {
        let old = MigrationTokenStore("fixture")
        let shared = MigrationTokenStore(nil)
        old.beforeDelete = {
            XCTAssertEqual(shared.reads, 2)
            XCTAssertEqual(shared.value, "fixture")
        }
        let migration = BossTokenMigration(legacy: old, shared: shared)
        try migration.migrate()
        try migration.migrate()
        XCTAssertNil(old.value)
        XCTAssertEqual(shared.value, "fixture")
        XCTAssertEqual(shared.writes, 1)
        XCTAssertEqual(old.deletes, 1)
    }

    func testReadAndWriteFailuresPreserveLegacyAndRetry() throws {
        for failure in ["shared-read", "legacy-read", "write", "verify"] {
            let old = MigrationTokenStore("fixture")
            let shared = MigrationTokenStore(nil)
            if failure == "legacy-read" { old.failRead = 1 }
            if failure == "shared-read" { shared.failRead = 1 }
            if failure == "write" { shared.failWrite = true }
            if failure == "verify" { shared.failRead = 2 }
            let migration = BossTokenMigration(legacy: old, shared: shared)
            XCTAssertThrowsError(try migration.migrate())
            XCTAssertEqual(old.value, "fixture")
            XCTAssertEqual(old.deletes, 0)
            old.failRead = nil
            shared.failRead = nil
            shared.failWrite = false
            try migration.migrate()
            XCTAssertNil(old.value)
            XCTAssertEqual(shared.value, "fixture")
        }
    }

    func testMissingOrMismatchedReadbackDoesNotDeleteLegacy() {
        for readback in [nil, "different"] {
            let old = MigrationTokenStore("fixture")
            let shared = MigrationTokenStore(nil)
            shared.writeOverride = { readback }
            XCTAssertThrowsError(try BossTokenMigration(legacy: old, shared: shared).migrate())
            XCTAssertEqual(old.value, "fixture")
            XCTAssertEqual(old.deletes, 0)
        }
    }

    func testDeleteFailureRetriesCleanupOnNextLaunch() throws {
        let old = MigrationTokenStore("fixture")
        let shared = MigrationTokenStore(nil)
        old.failDelete = true
        let migration = BossTokenMigration(legacy: old, shared: shared)
        XCTAssertThrowsError(try migration.migrate())
        XCTAssertEqual(old.value, "fixture")
        old.failDelete = false
        try migration.migrate()
        XCTAssertNil(old.value)
        XCTAssertEqual(shared.writes, 1)
    }
}

final class MigrationTokenStore: TokenRemoving, @unchecked Sendable {
    var value: String?
    var reads = 0
    var writes = 0
    var deletes = 0
    var failRead: Int?
    var failWrite = false
    var failDelete = false
    var writeOverride: (() -> String?)?
    var beforeDelete: (() -> Void)?

    init(_ value: String?) { self.value = value }
    func read() throws -> String? {
        reads += 1
        if reads == failRead { throw SettingsError.missingToken }
        return value
    }
    func write(_ token: String) throws {
        if failWrite { throw SettingsError.missingToken }
        writes += 1
        value = writeOverride.map { $0() } ?? token
    }
    func delete() throws {
        beforeDelete?()
        if failDelete { throw SettingsError.missingToken }
        deletes += 1
        value = nil
    }
}
