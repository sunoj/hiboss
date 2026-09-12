// Project identity decoding and stable native presentation contracts.
// Exports XCTest coverage for post objects, sessions and session-only projects.
import XCTest
@testable import HibossKit

final class ProjectIdentityTests: XCTestCase {
    @MainActor
    func testSessionInventoryFailureDoesNotFailMessageHistory() async {
        let store = OptionFlowStore()
        store.connect(api: FailedSessionInventory())
        defer { store.disconnect() }
        for _ in 0..<100 {
            if store.historyState == .loaded { break }
            if case .failed = store.historyState { break }
            await Task.yield()
        }
        XCTAssertEqual(store.historyState, .loaded)
        XCTAssertTrue(store.projectSessions.isEmpty)
    }

    func testPostDecodesIdentityAndRetainsItWhenLiked() throws {
        let data = Data(#"{"id":"post","project":{"id":"p","slug":"repo","display_name":"Renamed Repo"},"agent_id":"a","body":"Done","created_at":"2026-09-12T00:00:00Z"}"#.utf8)
        let post = try JSONDecoder().decode(ProgressPost.self, from: data)
        XCTAssertEqual(post.project, "repo")
        XCTAssertEqual(post.projectIdentity.id, "p")
        XCTAssertEqual(post.projectIdentity.displayName, "Renamed Repo")
        XCTAssertEqual(post.withLike(count: 1, liked: true).projectIdentity, post.projectIdentity)
        XCTAssertEqual(try JSONDecoder().decode(ProgressPost.self, from: JSONEncoder().encode(post)), post)
    }

    func testSessionsDecodeProjectAndPreferSlugOverStoredLabel() throws {
        let data = Data(#"{"id":"s","project_id":"p","project_slug":"repo","branch":"feat/a","label":"old-name/main"}"#.utf8)
        let session = try JSONDecoder().decode(ProjectSession.self, from: data)
        XCTAssertEqual(session.projectId, "p")
        XCTAssertEqual(session.projectSlug, "repo")
        XCTAssertEqual(session.displayLabel, "repo/feat/a")
    }

    func testSessionOnlyProjectHasNoLastPost() throws {
        let data = Data(#"{"project":"repo","count":0,"last_post_at":null,"agent_id":"a"}"#.utf8)
        let project = try JSONDecoder().decode(ProgressProject.self, from: data)
        XCTAssertEqual(project.id, "repo")
        XCTAssertNil(project.lastPostAt)
    }

    func testHomeKeysOnSlugWhenDisplayNameChanges() {
        let project = HomeProject(name: "Display Name", slug: "repo",
            sessions: .init(working: 1, waiting: 0, blocked: 0, idle: 0),
            pendingDecisions: 0, postCount7d: 0, lastPost: nil, lastActivityAt: "2026-09-12T00:00:00Z")
        XCTAssertEqual(project.id, "repo")
    }
}

private struct FailedSessionInventory: BossServing, SessionsServing {
    func messageStream() async -> AsyncThrowingStream<BossEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func feedStream() async -> AsyncThrowingStream<HistoryMessage, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func fetchHistory() async throws -> [HistoryMessage] { [] }
    func fetchMessage(_ messageID: MessageID) async throws -> MessageDetail {
        throw HibossAPIError.invalidResponse
    }
    func reply(to messageID: MessageID, with choice: String) async throws -> ReplyOutcome { .accepted }
    func projectSessions() async throws -> [ProjectSession] { throw HibossAPIError.invalidResponse }
}
