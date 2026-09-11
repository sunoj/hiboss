// Covers device management safety, failure recovery, and revoked inventory retention.
// Exports: BossClientsStoreTests with an isolated in-memory service.
// Dependencies: XCTest and HibossKit.

import Foundation
import XCTest
@testable import HibossKit

@MainActor
final class BossClientsStoreTests: XCTestCase {
    func testCurrentAndAlreadyRevokedDevicesCannotBeRevoked() async throws {
        let api = try InventoryAPI()
        let store = BossClientsStore(api: api)
        await store.load()
        await store.revoke(try XCTUnwrap(store.clients.first { $0.isCurrent }))
        await store.revoke(try XCTUnwrap(store.clients.first { $0.revokedAt != nil }))
        let revokedIDs = await api.revokedIDs
        XCTAssertTrue(revokedIDs.isEmpty)
    }

    func testConfirmedRevocationUpdatesInventoryAndRemovesPushBadge() async throws {
        let api = try InventoryAPI()
        let store = BossClientsStore(api: api)
        await store.load()
        let other = try XCTUnwrap(store.clients.first { $0.canRevoke })
        await store.revoke(other)
        let revoked = try XCTUnwrap(store.clients.first { $0.id == other.id })
        XCTAssertFalse(revoked.canRevoke)
        XCTAssertFalse(revoked.hasPushDevice)
        XCTAssertTrue(revoked.hasSigningKey)
        XCTAssertNil(store.error)
        let revokedIDs = await api.revokedIDs
        XCTAssertEqual(revokedIDs, [other.id])
    }

    func testRevokeFailureKeepsDeviceActiveAndSurfacesError() async throws {
        let api = try InventoryAPI()
        await api.failRevocation()
        let store = BossClientsStore(api: api)
        await store.load()
        let other = try XCTUnwrap(store.clients.first { $0.canRevoke })
        await store.revoke(other)
        XCTAssertEqual(store.clients.first { $0.id == other.id }, other)
        XCTAssertNotNil(store.error)
        XCTAssertFalse(store.isBusy)
    }

    func testFailedRefreshAfterSuccessfulRevokeDoesNotRestoreRevokeButton() async throws {
        let api = try InventoryAPI()
        let store = BossClientsStore(api: api)
        await store.load()
        await api.failListing()
        let other = try XCTUnwrap(store.clients.first { $0.canRevoke })
        await store.revoke(other)
        XCTAssertFalse(try XCTUnwrap(store.clients.first { $0.id == other.id }).canRevoke)
        XCTAssertNotNil(store.error)
    }

    func testLoadFailureCanBeRetried() async throws {
        let api = try InventoryAPI()
        await api.failListing()
        let store = BossClientsStore(api: api)
        await store.load()
        XCTAssertNotNil(store.error)
        XCTAssertFalse(store.isBusy)
        await api.allowListing()
        await store.load()
        XCTAssertNil(store.error)
        XCTAssertEqual(store.clients.count, 3)
    }
}

private actor InventoryAPI: BossClientsServing {
    private var clients: [BossClient]
    private var listingFails = false
    private var revocationFails = false
    var revokedIDs: [BossClientID] = []

    init() throws {
        let json = #"{"id":"other","kind":"ios","label":"Phone","created_at":"2026-09-11 10:00:00","last_seen_at":null,"revoked_at":null,"has_push_device":true,"has_signing_key":true,"is_current":false}"#
        let current = json.replacingOccurrences(of: "other", with: "current")
            .replacingOccurrences(of: "\"is_current\":false", with: "\"is_current\":true")
        let revoked = json.replacingOccurrences(of: "other", with: "revoked")
            .replacingOccurrences(of: "\"revoked_at\":null", with: "\"revoked_at\":\"2026-09-11 11:00:00\"")
        clients = try [current, json, revoked].map {
            try JSONDecoder().decode(BossClient.self, from: Data($0.utf8))
        }
    }

    func failListing() { listingFails = true }
    func allowListing() { listingFails = false }
    func failRevocation() { revocationFails = true }
    func verifyConnection() async throws {}
    func createClient(kind: BossClientKind, label: String) async throws -> BossClientGrant {
        throw HibossAPIError.invalidResponse
    }
    func listClients() async throws -> [BossClient] {
        if listingFails { throw HibossAPIError.invalidResponse }
        return clients
    }
    func revokeClient(id: BossClientID) async throws {
        if revocationFails { throw HibossAPIError.invalidResponse }
        revokedIDs.append(id)
        guard let index = clients.firstIndex(where: { $0.id == id }) else { return }
        clients[index].revokedAt = "2026-09-11 11:00:00"
        clients[index].hasPushDevice = false
    }
}
