// Covers native history publication and deletion when a stored credential is removed.
// Exports HistoryCacheIntegrationTests using isolated defaults and cache directories.
// Depends on XCTest, Combine, HibossIsland, and HibossKit; no network calls.

import Combine
import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class HistoryCacheIntegrationTests: XCTestCase {
    func testFlowDoesNotRepublishAnIdenticalFullRefresh() async {
        let flow = OptionFlowStore()
        flow.connect(api: CacheFlowAPI())
        await flow.refreshHistory()
        var publications = 0
        let observation = flow.$historyMessages.dropFirst().sink { _ in publications += 1 }
        await flow.refreshHistory()
        XCTAssertEqual(flow.historyMessages.map(\.id), ["cached"])
        XCTAssertEqual(publications, 0)
        observation.cancel()
        flow.disconnect()
    }

    func testCredentialRemovalDeletesHistoryCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "HistoryRemoval.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        let config = ConnectionConfig(serverURL: URL(string: "https://cached.test")!, bossToken: "synthetic")
        let cache = HistoryCache(directory: directory)
        let sync = HistorySync(api: CacheFlowAPI(config: config), cache: cache) { _, _ in }
        await sync.synchronize()
        await sync.stop()
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        defaults.set(config.serverURL.absoluteString, forKey: AppConstants.Storage.serverURL)
        let settings = AppSettings(defaults: defaults, historyCache: cache, keychain: HistoryTokenFixture())
        await settings.loadToken()
        settings.bossToken = ""
        await settings.historyCacheDeletion?.value
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
}

private struct CacheFlowAPI: BossServing {
    let config: ConnectionConfig?
    init(config: ConnectionConfig? = nil) { self.config = config }
    var historyCacheKey: HistoryCacheKey? { config.map { HistoryCacheKey(config: $0) } }
    func fetchHistoryBossID() async throws -> String? { "boss" }
    func fetchHistoryPage(updatedAfter: String?) async throws -> HistoryResponse {
        let row = HistoryMessage(id: "cached", body: "Cached", direction: "agent_to_boss",
            status: "delivered", priority: "normal", createdAt: "2026-10-01T00:00:00Z")
        return HistoryResponse(messages: [row], total: 1, cursor: "2026-10-10 10:20:30")
    }
    func fetchHistory() async throws -> [HistoryMessage] { [] }
    func messageStream() async -> AsyncThrowingStream<BossEvent, Error> { AsyncThrowingStream { _ in } }
    func feedStream() async -> AsyncThrowingStream<HistoryMessage, Error> { AsyncThrowingStream { _ in } }
    func fetchMessage(_ messageID: MessageID) async throws -> MessageDetail { throw URLError(.badURL) }
    func reply(to messageID: MessageID, with choice: String) async throws -> ReplyOutcome { .accepted }
}

private struct HistoryTokenFixture: TokenStoring {
    func read() throws -> String? { "synthetic" }
    func write(_ token: String) throws {}
}
