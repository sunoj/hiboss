// Verifies the sidebar's session sections: state order, empty sections, and search.
// Exports: SidebarSessionGroupsTests and SidebarSessionRowTests (logic only; open no windows).
// Dependencies: XCTest, HibossKit SessionDirectory, and SidebarSessionGroup.

import HibossKit
import XCTest
@testable import HibossIsland

final class SidebarSessionGroupsTests: XCTestCase {
    func testSectionsFollowNeedsYouWorkingIdleOrder() {
        let groups = SidebarSessionGroup.groups(SessionDirectoryFixture.directory(), query: "") { $0.projectLabel }
        XCTAssertEqual(groups.map(\.kind), [.needsYou, .working, .idle])
        XCTAssertEqual(groups.map { $0.sessions.map(\.id) }, [["ask"], ["build"], ["old"]])
        XCTAssertEqual(groups.map(\.title), [L("Needs you"), L("Working"), L("Idle")])
    }

    func testSearchKeepsOnlySectionsWithMatches() {
        let groups = SidebarSessionGroup.groups(SessionDirectoryFixture.directory(), query: "  router ") { $0.projectLabel }
        XCTAssertEqual(groups.map(\.kind), [.working])
        XCTAssertEqual(groups.first?.sessions.map(\.id), ["build"])
        XCTAssertTrue(SidebarSessionGroup.groups(SessionDirectoryFixture.directory(), query: "nothing") { $0.projectLabel }.isEmpty)
    }

    func testSearchMatchesAgentAndBranch() {
        let byAgent = SidebarSessionGroup.groups(SessionDirectoryFixture.directory(), query: "codex") { $0.projectLabel }
        XCTAssertEqual(byAgent.flatMap { $0.sessions.map(\.id) }, ["old"])
        let byBranch = SidebarSessionGroup.groups(SessionDirectoryFixture.directory(), query: "feat-retry") { $0.projectLabel }
        XCTAssertEqual(byBranch.flatMap { $0.sessions.map(\.id) }, ["build"])
    }
}

final class SidebarSessionRowTests: XCTestCase {
    /// A session's row id carries no section, so a session that changes state keeps its row.
    func testSessionRowIdDoesNotDependOnItsSection() {
        let groups = SidebarSessionGroup.groups(SessionDirectoryFixture.directory(), query: "") { $0.projectLabel }
        let rows = SidebarSessionRow.rows(groups)
        XCTAssertEqual(rows.map(\.id), ["header.needsYou", "session.ask", "header.working", "session.build",
            "header.idle", "session.old"])
        XCTAssertTrue(SidebarSessionRow.rows([]).isEmpty)
    }
}

private enum SessionDirectoryFixture {
    static func directory() -> SessionDirectory {
        let ask = message("ask", label: "hiboss", age: 20, status: "waiting",
            metadata: MessageMetadata(options: ["Ship", "Hold"]))
        let history = [
            ask,
            message("build", label: "smart-router", age: 10, status: "working", branch: "feat-retry"),
            message("old", label: "discover-more", age: 10_000, status: nil, agent: "ming-codex"),
        ]
        return SessionDirectory(history: history, requiredInputs: [ask], now: .now)
    }

    private static func message(_ session: String, label: String, age: TimeInterval, status: String?,
                         branch: String = "main", agent: String = "ming-claude",
                         metadata: MessageMetadata? = nil) -> HistoryMessage {
        HistoryMessage(id: MessageID(rawValue: session), body: "Update from \(label)",
            agentName: agent, direction: "agent_to_boss", status: "delivered", priority: "normal",
            metadata: metadata, createdAt: AttentionTestSupport.iso(Date.now.addingTimeInterval(-age)),
            sessionId: session, sessionLabel: label, sessionBranch: branch, sessionStatus: status)
    }
}
