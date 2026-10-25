// Exercises authenticated response rejection and replacement-account isolation.
// Exports APIAccountAuthorizationTests using synthetic HTTP responses and shared subscriptions.
// Dependencies: XCTest, HibossAPI and AccountAuthorization; no live server.

import Combine
import XCTest
@testable import HibossKit

@MainActor
final class APIAccountAuthorizationTests: XCTestCase {
    func testCommonValidationRejectsOnlyTheCurrentAccountOnce() async throws {
        let account = ConnectionConfig(serverURL: try XCTUnwrap(URL(string: "https://unit.test")),
                                       bossToken: "unit-token")
        let api = HibossAPI(config: account)
        let boundary = AccountAuthorization.shared
        defer { boundary.connect(nil) }
        let status = 401
        boundary.connect(account)
        var rejections = 0
        var identityChanges = 0
        let observation = boundary.observe { error in
            if AccountAuthorization.isRejected(error) { rejections += 1 }
            else { identityChanges += 1 }
        }
        let response = try XCTUnwrap(HTTPURLResponse(url: account.serverURL, statusCode: status,
                                                    httpVersion: nil, headerFields: nil))
        for _ in 0..<2 {
            do { try await api.validate(response); XCTFail("Expected rejection") }
            catch { XCTAssertEqual((error as? HibossAPIError)?.isAuthFailure, true) }
        }
        XCTAssertEqual(rejections, 1)
        boundary.connect(ConnectionConfig(serverURL: account.serverURL, bossToken: "replacement-token"))
        XCTAssertEqual(identityChanges, 1, "Account replacement must clear previous content")
        do { try await api.validate(response); XCTFail("Expected original API error") }
        catch { XCTAssertEqual((error as? HibossAPIError)?.isAuthFailure, true) }
        XCTAssertEqual(rejections, 1, "Old credentials must not clear a replacement account")
        XCTAssertEqual(identityChanges, 1, "Old credentials must not invalidate the new identity")
        observation.cancel()
    }

    func testRejectionPurgesUnmountedQuestionnaireDraftsOnlyForTheRejectedServer() throws {
        let boundary = AccountAuthorization()
        let account = ConnectionConfig(serverURL: try XCTUnwrap(URL(string: "https://drafts.unit.test")),
                                       bossToken: "unit-token")
        let rejected = "hiboss.questionnaire.https://drafts.unit.test.boss.request.1"
        let other = "hiboss.questionnaire.https://other-drafts.unit.test.boss.request.1"
        let storage = UserDefaults.standard
        storage.set("Private draft", forKey: rejected)
        storage.set("Other draft", forKey: other)
        defer {
            storage.removeObject(forKey: rejected)
            storage.removeObject(forKey: other)
        }
        boundary.connect(account)
        boundary.reject(HibossAPIError.requestFailed(status: 401, message: ""), account: account)
        XCTAssertNil(storage.object(forKey: rejected))
        XCTAssertEqual(storage.string(forKey: other), "Other draft")
    }

    func testAccountChangePurgesUnmountedDraftsOnlyForThePreviousServer() throws {
        let boundary = AccountAuthorization()
        let account = ConnectionConfig(serverURL: try XCTUnwrap(URL(string: "https://old-drafts.unit.test")),
                                       bossToken: "unit-token")
        let next = ConnectionConfig(serverURL: try XCTUnwrap(URL(string: "https://next-drafts.unit.test")),
                                    bossToken: "unit-token")
        let oldDraft = "hiboss.questionnaire.https://old-drafts.unit.test.boss.request.1"
        let nextDraft = "hiboss.questionnaire.https://next-drafts.unit.test.boss.request.1"
        let storage = UserDefaults.standard
        boundary.connect(account)
        storage.set("Previous account draft", forKey: oldDraft)
        storage.set("Next account draft", forKey: nextDraft)
        defer {
            storage.removeObject(forKey: oldDraft)
            storage.removeObject(forKey: nextDraft)
        }
        let generation = boundary.generation
        boundary.connect(next)
        XCTAssertEqual(boundary.generation, generation + 1)
        XCTAssertFalse(boundary.hasRejectedAccount)
        XCTAssertNil(storage.object(forKey: oldDraft))
        XCTAssertEqual(storage.string(forKey: nextDraft), "Next account draft")
    }

    func testCommonValidationRetainsContentForOrdinaryResponseErrors() async throws {
        let account = ConnectionConfig(serverURL: try XCTUnwrap(URL(string: "https://unit.test")),
                                       bossToken: "unit-token")
        AccountAuthorization.shared.connect(account)
        defer { AccountAuthorization.shared.connect(nil) }
        let api = HibossAPI(config: account)
        var rejections = 0
        let observation = AccountAuthorization.shared.observe { _ in rejections += 1 }
        defer { observation.cancel() }
        for status in [200, 403, 404, 409, 503] {
            let response = try XCTUnwrap(HTTPURLResponse(url: account.serverURL, statusCode: status,
                                                        httpVersion: nil, headerFields: nil))
            do {
                try await api.validate(response)
                XCTAssertEqual(status, 200)
            } catch { XCTAssertFalse((error as? HibossAPIError)?.isAuthFailure ?? true) }
        }
        XCTAssertEqual(rejections, 0)
    }
}
