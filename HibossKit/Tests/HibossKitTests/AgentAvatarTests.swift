// Agent decoding, authenticated fetch, and account-isolated avatar refresh coverage.
// Dependencies: XCTest, URLProtocol, and HibossKit observable avatar lookup.

import XCTest
@testable import HibossKit

@MainActor
final class AgentAvatarTests: XCTestCase {
    private let url = URL(string: "https://images.example/avatar.png")

    func testDecodeRegisteredAvatarAndOlderServersWithoutAvatarField() throws {
        let registered = try JSONDecoder().decode(BossAgent.self, from: Data(
            #"{"id":"a1","name":"Build Agent","avatar_url":"https://images.example/avatar.png"}"#.utf8))
        XCTAssertEqual(registered.avatarURL, url)
        for payload in [#"{"id":"a1","name":"Build Agent"}"#,
                        #"{"id":"a1","name":"Build Agent","avatar_url":null}"#] {
            let agent = try JSONDecoder().decode(BossAgent.self, from: Data(payload.utf8))
            XCTAssertNil(agent.avatarURL)
        }
    }

    func testFetchUsesAuthenticatedBossAgentsEndpoint() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AgentsURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let api = HibossAPI(config: ConnectionConfig(
            serverURL: try XCTUnwrap(URL(string: "https://hiboss.example")), bossToken: "test-token"),
            session: session)
        let agents = try await api.fetchAgents()
        XCTAssertEqual(agents, [BossAgent(id: "a1", name: "Build Agent", avatarURL: url)])
    }

    func testLookupUsesExactNameOnlyAndRejectsNonPublicURLs() {
        let store = AgentAvatarStore(agents: [BossAgent(id: "a1", name: "Build Agent", avatarURL: url)])
        XCTAssertNil(store.url(forName: "a1"))
        XCTAssertEqual(store.url(forName: "Build Agent"), url)
        XCTAssertNil(store.url(forName: "build agent"))
        for invalid in ["file:///tmp/avatar.png", "https://user:password@example.com/a.png", "relative.png"] {
            let invalidStore = AgentAvatarStore(agents: [
                BossAgent(id: "a1", name: "Build Agent", avatarURL: URL(string: invalid))])
            XCTAssertNil(invalidStore.url(forName: "Build Agent"))
        }
    }

    func testNameMatchingAnotherAgentIDUsesOnlyItsOwnAvatar() {
        let foreignID = "0123456789abcdef0123456789abcdef"
        let ownURL = URL(string: "https://images.example/own.png")
        for avatarURL in [ownURL, nil] {
            let store = AgentAvatarStore(agents: [
                BossAgent(id: foreignID, name: "Other Agent", avatarURL: url),
                BossAgent(id: "own", name: foreignID, avatarURL: avatarURL)
            ])
            XCTAssertEqual(store.url(forName: foreignID), avatarURL)
            XCTAssertNotEqual(store.url(forName: foreignID), url)
        }
    }

    func testReconnectRefreshReplacesChangedAndRemovedAvatars() async {
        let api = HeldAgentsAPI()
        let store = AgentAvatarStore()
        store.connect(api: api)
        await waitUntil { await api.pending == 1 }
        await api.complete([BossAgent(id: "a1", name: "Build Agent", avatarURL: url)])
        await waitUntil { store.url(forName: "Build Agent") == self.url }
        store.refresh()
        await waitUntil { await api.pending == 1 }
        let changed = URL(string: "https://images.example/changed.png")
        await api.complete([BossAgent(id: "a1", name: "Build Agent", avatarURL: changed)])
        await waitUntil { store.url(forName: "Build Agent") == changed }
        store.refresh()
        await waitUntil { await api.pending == 1 }
        await api.complete([BossAgent(id: "a1", name: "Build Agent")])
        await waitUntil { store.url(forName: "Build Agent") == nil }
        store.disconnect()
    }

    func testAccountSwitchAndSignOutRejectLateResponsesEvenWithSameAgentName() async {
        let first = HeldAgentsAPI()
        let next = HeldAgentsAPI()
        let store = AgentAvatarStore(agents: [BossAgent(id: "a1", name: "Build Agent", avatarURL: url)])
        store.connect(api: first)
        XCTAssertNil(store.url(forName: "Build Agent"))
        await waitUntil { await first.pending == 1 }
        store.connect(api: next)
        await waitUntil { await next.pending == 1 }
        let nextURL = URL(string: "https://next.example/avatar.png")
        await next.complete([BossAgent(id: "a1", name: "Build Agent", avatarURL: nextURL)])
        await waitUntil { store.url(forName: "Build Agent") == nextURL }
        await first.complete([BossAgent(id: "a1", name: "Build Agent", avatarURL: url)])
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(store.url(forName: "Build Agent"), nextURL)
        store.refresh()
        await waitUntil { await next.pending == 1 }
        store.disconnect()
        await next.complete([BossAgent(id: "a1", name: "Build Agent", avatarURL: nextURL)])
        for _ in 0..<100 { await Task.yield() }
        XCTAssertNil(store.url(forName: "a1"))
        XCTAssertNil(store.url(forName: "Build Agent"))
    }

    private func waitUntil(_ condition: () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if await condition() { return }
            await Task.yield()
        }
        XCTFail("Avatar refresh did not complete")
    }
}

private actor HeldAgentsAPI: AgentsServing {
    private var continuation: CheckedContinuation<[BossAgent], Never>?
    var pending: Int { continuation == nil ? 0 : 1 }

    func fetchAgents() async throws -> [BossAgent] {
        await withCheckedContinuation { continuation = $0 }
    }

    func complete(_ agents: [BossAgent]) {
        let pending = continuation
        continuation = nil
        pending?.resume(returning: agents)
    }
}

private final class AgentsURLProtocol: HTTPTestProtocol, @unchecked Sendable {

    override func startLoading() {
        XCTAssertEqual(request.url?.path, "/api/boss/agents")
        XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        guard let url = request.url, let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let payload = """
        {"agents":[{"id":"a1","name":"Build Agent","avatar_url":"https://images.example/avatar.png"}]}
        """
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
