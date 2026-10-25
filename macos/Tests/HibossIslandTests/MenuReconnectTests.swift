// Exercises rejection recovery through the actual AppKit status-menu Reconnect action.
// Exports MenuReconnectTests with isolated settings and synthetic HTTP responses.
// Dependencies: AppKit, Combine, XCTest, HibossKit and AppDelegate.

import AppKit
import Combine
import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class MenuReconnectTests: XCTestCase {
    func testMenuReconnectPublishesVerifiedAccountAndRestoresPreferencesAndDevices() async throws {
        let (delegate, api) = try await fixture()
        defer { cleanup(delegate) }
        AccountAuthorization.shared.reject(HibossAPIError.requestFailed(status: 401, message: ""))
        XCTAssertNil(delegate.settings.activeClientConfig)
        XCTAssertTrue(delegate.preferencesStore.authorizationRejected)
        XCTAssertTrue(delegate.joinRequests.isForbidden)
        let loaded = expectation(description: "menu reconnect reloads preferences")
        let observer = delegate.preferencesStore.$state.sink { state in
            if state == .loaded { loaded.fulfill() }
        }
        defer { observer.cancel() }
        try clickReconnect(delegate)
        await fulfillment(of: [loaded], timeout: 2)
        let verifications = await api.verifications
        XCTAssertEqual(verifications, 1, "Menu reconnect must verify stored credentials")
        XCTAssertNotNil(delegate.settings.activeClientConfig,
                        "Accepted config must reach Box/Progress/Panels")
        XCTAssertFalse(AccountAuthorization.shared.hasRejectedAccount)
        XCTAssertFalse(delegate.preferencesStore.authorizationRejected)
        XCTAssertEqual(delegate.preferencesStore.preferences.privatePush, true)
        await delegate.joinRequests.refresh()
        XCTAssertFalse(delegate.joinRequests.isForbidden)
        XCTAssertTrue(delegate.joinRequests.didLoad)
        XCTAssertEqual(delegate.flow.connectionState, .connected)
        try await verifyContentProviders(settings: delegate.settings)
    }

    func testMenuReconnectWithRejectedCredentialsDoesNotRestoreAccount() async throws {
        let (delegate, api) = try await fixture()
        defer { cleanup(delegate) }
        AccountAuthorization.shared.reject(HibossAPIError.requestFailed(status: 401, message: ""))
        await api.rejectVerification()
        let checked = expectation(description: "menu reconnect verifies credentials")
        await api.onVerification { checked.fulfill() }
        try clickReconnect(delegate)
        await fulfillment(of: [checked], timeout: 2)
        XCTAssertNil(delegate.settings.activeClientConfig)
        XCTAssertTrue(AccountAuthorization.shared.hasRejectedAccount)
        XCTAssertTrue(delegate.preferencesStore.authorizationRejected)
        XCTAssertTrue(delegate.joinRequests.isForbidden)
        XCTAssertNotEqual(delegate.flow.connectionState, .connected)
    }

    private func fixture() async throws -> (AppDelegate, ReconnectClientsAPI) {
        AccountAuthorization.shared.connect(nil)
        XCTAssertTrue(URLProtocol.registerClass(ReconnectHTTPProtocol.self))
        let suite = "MenuReconnectTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        defaults.set("https://menu-reconnect.invalid", forKey: AppConstants.Storage.serverURL)
        let api = ReconnectClientsAPI()
        let settings = AppSettings(defaults: defaults, keychain: ReconnectTokens(), clientsAPI: { _ in api })
        await settings.loadToken()
        let delegate = AppDelegate(settings: settings)
        delegate.setStatusItemVisible(true)
        return (delegate, api)
    }

    private func clickReconnect(_ delegate: AppDelegate) throws {
        let menu = try XCTUnwrap(delegate.statusItem?.menu)
        let index = try XCTUnwrap(menu.items.firstIndex { $0.title == L("Reconnect") })
        XCTAssertTrue(menu.items[index].target === delegate)
        menu.performActionForItem(at: index)
    }

    private func verifyContentProviders(settings: AppSettings) async throws {
        let box = BoxBrowserStore { settings.activeClientConfig.map { HibossAPI(config: $0) } }
        let progress = ProgressFeedStore { settings.activeClientConfig.map { HibossAPI(config: $0) } }
        let panels = PanelsModel(api: settings.activeClientConfig.map { HibossAPI(config: $0) },
            configurationProvider: {
            try XCTUnwrap(settings.activeClientConfig)
        }, demoMode: false, autoload: false)
        await box.refresh()
        await progress.refresh()
        await panels.load()
        XCTAssertTrue(box.hasResult)
        XCTAssertNil(box.error)
        XCTAssertTrue(progress.hasResult)
        XCTAssertNil(progress.loadError)
        XCTAssertEqual(panels.loadState, .loaded)
    }

    private func cleanup(_ delegate: AppDelegate) {
        delegate.setStatusItemVisible(false)
        delegate.requiredInputs.disconnect()
        delegate.flow.disconnect()
        delegate.notifications.disconnect()
        AccountAuthorization.shared.connect(nil)
        URLProtocol.unregisterClass(ReconnectHTTPProtocol.self)
    }
}

private struct ReconnectTokens: TokenStoring {
    func read() throws -> String? { "synthetic-menu-token" }
    func write(_ token: String) throws {}
}

private actor ReconnectClientsAPI: BossClientsServing {
    private(set) var verifications = 0
    private var rejected = false
    private var verified: (@Sendable () -> Void)?
    func rejectVerification() { rejected = true }
    func onVerification(_ callback: @escaping @Sendable () -> Void) { verified = callback }
    func verifyConnection() async throws {
        verifications += 1
        verified?()
        if rejected { throw HibossAPIError.requestFailed(status: 401, message: "") }
    }
    func createClient(kind: BossClientKind, label: String) async throws -> BossClientGrant {
        XCTFail("Reconnect must not mint another client")
        throw URLError(.badServerResponse)
    }
    func listClients() async throws -> [BossClient] { [] }
    func revokeClient(id: BossClientID) async throws { XCTFail("Reconnect must not revoke a client") }
}

private final class ReconnectHTTPProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "menu-reconnect.invalid"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let body: String
        switch url.path {
        case "/api/boss/me/preferences": body = #"{"private_push":true}"#
        case "/api/boss/join-requests": body = #"{"requests":[]}"#
        case "/api/box/collections": body = #"{"collections":[]}"#
        case "/api/box/items": body = #"{"items":[],"next_cursor":null}"#
        case "/api/progress": body = #"{"posts":[],"next_cursor":null}"#
        case "/api/progress/projects": body = #"{"projects":[]}"#
        case "/api/panels": body = #"{"panels":[],"next_cursor":null}"#
        case "/api/interaction-requests": body = #"{"requests":[],"next_cursor":null}"#
        default: body = #"{"messages":[],"sessions":[],"agents":[],"total":0}"#
        }
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
