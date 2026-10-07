// Verifies explicit and default access groups on every token Keychain operation.
// Exports KeychainAccessGroupTests with a Security API recording boundary.
// Dependencies: XCTest, Security and the testable HibossKit module.

import Security
import XCTest
@testable import HibossKit

final class KeychainAccessGroupTests: XCTestCase {
    func testEveryOperationUsesOnlyTheSelectedAccessGroup() throws {
        for group in [nil, "TEAM.ai.hiboss.shared"] {
            let backend = RecordingKeychain()
            let store = KeychainStore(service: "fixture-service", account: "boss-token",
                accessGroup: group, operations: backend)
            XCTAssertEqual(try store.read(), "fixture")
            try store.write("updated")
            backend.updateStatus = errSecItemNotFound
            try store.write("new")
            try store.delete()
            XCTAssertEqual(backend.queries.count, 5)
            for query in backend.queries {
                XCTAssertEqual(query[kSecAttrService as String] as? String, "fixture-service")
                XCTAssertEqual(query[kSecAttrAccount as String] as? String, "boss-token")
                XCTAssertEqual(query[kSecAttrAccessGroup as String] as? String, group)
            }
        }
    }

    func testReadMissingAndInvalidBytesReturnNilAndErrorsThrow() throws {
        let backend = RecordingKeychain()
        let store = makeStore(backend)
        backend.readStatus = errSecItemNotFound
        XCTAssertNil(try store.read())
        backend.readStatus = errSecSuccess
        backend.data = nil
        XCTAssertNil(try store.read())
        backend.data = Data([0xff])
        XCTAssertNil(try store.read())
        backend.readStatus = errSecMissingEntitlement
        XCTAssertThrowsError(try store.read())
    }

    func testFailedUpdateNeverAddsAndAddErrorsThrow() {
        let backend = RecordingKeychain()
        let store = makeStore(backend)
        backend.updateStatus = errSecMissingEntitlement
        XCTAssertThrowsError(try store.write("fixture"))
        XCTAssertEqual(backend.queries.count, 1)
        backend.updateStatus = errSecItemNotFound
        backend.addStatus = errSecDuplicateItem
        XCTAssertThrowsError(try store.write("fixture"))
        XCTAssertEqual(backend.queries.count, 3)
    }

    func testDeleteAcceptsMissingButPropagatesOtherErrors() throws {
        let backend = RecordingKeychain()
        let store = makeStore(backend)
        backend.deleteStatus = errSecItemNotFound
        try store.delete()
        backend.deleteStatus = errSecMissingEntitlement
        XCTAssertThrowsError(try store.delete())
    }

    private func makeStore(_ backend: RecordingKeychain) -> KeychainStore {
        KeychainStore(service: "fixture-service", account: "boss-token",
            accessGroup: "TEAM.ai.hiboss.shared", operations: backend)
    }
}

private final class RecordingKeychain: KeychainOperating, @unchecked Sendable {
    var queries: [[String: Any]] = []
    var readStatus = errSecSuccess
    var updateStatus = errSecSuccess
    var addStatus = errSecSuccess
    var deleteStatus = errSecSuccess
    var data: Data? = Data("fixture".utf8)

    func read(_ query: [String: Any]) -> (OSStatus, Data?) {
        queries.append(query)
        return (readStatus, data)
    }
    func update(_ query: [String: Any], data: Data) -> OSStatus {
        queries.append(query)
        return updateStatus
    }
    func add(_ item: [String: Any]) -> OSStatus {
        queries.append(item)
        return addStatus
    }
    func delete(_ query: [String: Any]) -> OSStatus {
        queries.append(query)
        return deleteStatus
    }
}
