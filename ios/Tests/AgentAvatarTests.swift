// Rendered registered avatars, loading/error initials, and circular image clipping.
// Dependencies: SwiftUI ImageRenderer, UIKit, XCTest, and native AgentAvatarView.

import HibossKit
import SwiftUI
import XCTest
@testable import HiBoss

@MainActor
final class AgentAvatarTests: XCTestCase {
    func testUnidentifiedMessageRowsKeepInitialsWhenFallbackNameHasAvatar() throws {
        let previous = ProcessInfo.processInfo.environment["HIBOSS_DEMO"]
        setenv("HIBOSS_DEMO", "1", 1)
        defer {
            if let previous { setenv("HIBOSS_DEMO", previous, 1) }
            else { unsetenv("HIBOSS_DEMO") }
        }
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-11T12:00:00Z"))
        for agentName: String? in [nil, "", " \n"] {
            let message = HistoryMessage(id: "unidentified", body: "Build finished", agentName: agentName,
                direction: "agent_to_boss", status: "delivered", priority: "normal",
                createdAt: "2026-10-11T12:00:00Z")
            let avatars = AgentAvatarStore(agents: [AgentAvatarDemo.agent(name: "Agent"),
                AgentAvatarDemo.agent(name: message.displayName)])
            let row = HistoryRow(message: message)
            XCTAssertEqual(try rendered(row.environment(\.agentAvatars, avatars)), try rendered(row))
            let snapshot = TodaySnapshot(history: [message], health: .live(checkedAt: now),
                coverageComplete: true, now: now)
            XCTAssertEqual(snapshot.delivered.map(\.id), [message.id])
            let today = TodayResults(snapshot: snapshot).frame(width: 390)
            XCTAssertEqual(try rendered(today.environment(\.agentAvatars, avatars)), try rendered(today))
        }
    }

    func testMissingAndBlankLookupNamesPreserveDisplayInitials() throws {
        let avatars = AgentAvatarStore(agents: [AgentAvatarDemo.agent(name: "Agent")])
        let initials = AgentAvatarContent(name: "Agent", size: 40, phase: .empty)
        for lookupName: String? in [nil, "", " \n"] {
            let view = AgentAvatarView(name: "Agent", size: 40, lookupName: lookupName)
                .environment(\.agentAvatars, avatars)
            XCTAssertEqual(try rendered(view), try rendered(initials))
        }
        for name in ["", " \n"] {
            let store = AgentAvatarStore(agents: [AgentAvatarDemo.agent(name: name)])
            let view = AgentAvatarView(name: name, size: 40).environment(\.agentAvatars, store)
            XCTAssertEqual(try rendered(view),
                try rendered(AgentAvatarContent(name: name, size: 40, phase: .empty)))
        }
    }

    func testRegisteredDemoLookupReplacesInitialsInAvatarView() throws {
        let previous = ProcessInfo.processInfo.environment["HIBOSS_DEMO"]
        setenv("HIBOSS_DEMO", "1", 1)
        defer {
            if let previous { setenv("HIBOSS_DEMO", previous, 1) }
            else { unsetenv("HIBOSS_DEMO") }
        }
        let avatars = AgentAvatarStore(agents: [AgentAvatarDemo.agent(name: "worker-design")])
        let view = AgentAvatarView(name: "worker-design", size: 40).environment(\.agentAvatars, avatars)
        let image = try XCTUnwrap(AgentAvatarDemo.image)
        XCTAssertEqual(try rendered(view),
            try rendered(AgentAvatarContent(name: "worker-design", size: 40, phase: .success(image))))
        XCTAssertNotEqual(try rendered(view),
            try rendered(AgentAvatarContent(name: "worker-design", size: 40, phase: .empty)))
    }

    func testAvatarLayoutRemainsSquareForEveryPhaseAndProposal() throws {
        let image = try XCTUnwrap(AgentAvatarDemo.image)
        let phases: [AsyncImagePhase] = [.empty, .failure(URLError(.cannotConnectToHost)), .success(image)]
        for size: CGFloat in [20, 22, 40, 80] {
            for proposal in [CGSize(width: 8, height: 8), CGSize(width: 400, height: 800)] {
                for phase in phases {
                    let host = UIHostingController(rootView: AgentAvatarContent(
                        name: "Long Agent Name", size: size, phase: phase)
                        .environment(\.dynamicTypeSize, .accessibility5))
                    XCTAssertEqual(host.sizeThatFits(in: proposal), CGSize(width: size, height: size))
                }
                let avatars = AgentAvatarStore(agents: [BossAgent(id: "pending", name: "Long Agent Name",
                    avatarURL: URL(string: "https://demo.hiboss.invalid/pending.png"))])
                for lookup in [AgentAvatarStore(), avatars] {
                    let view = AgentAvatarView(name: "Long Agent Name", size: size)
                    let host = UIHostingController(rootView: view
                        .environment(\.agentAvatars, lookup).environment(\.dynamicTypeSize, .accessibility5))
                    XCTAssertEqual(host.sizeThatFits(in: proposal), CGSize(width: size, height: size))
                }
            }
        }
    }

    func testBundledDemoAvatarRendersAnImage() throws {
        let image = try XCTUnwrap(AgentAvatarDemo.image)
        let success = AgentAvatarContent(name: "worker-design", size: 40, phase: .success(image))
        let initials = AgentAvatarContent(name: "worker-design", size: 40, phase: .empty)
        XCTAssertNotEqual(try rendered(success), try rendered(initials))
    }

    func testLoadingFailureAndMissingAvatarKeepExistingInitials() throws {
        let empty = AgentAvatarContent(name: "Build Agent", size: 40, phase: .empty)
        let failure = AgentAvatarContent(name: "Build Agent", size: 40,
            phase: .failure(URLError(.cannotConnectToHost)))
        XCTAssertEqual(try rendered(empty), try rendered(failure))
        XCTAssertEqual(try rendered(AgentAvatarView(name: "Build Agent", size: 40)), try rendered(empty))
        XCTAssertNotEqual(try rendered(empty),
            try rendered(AgentAvatarContent(name: "Other Worker", size: 40, phase: .empty)))
    }

    func testSuccessfulImageReplacesInitialsAndStaysCircular() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 40)).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
        }
        for size: CGFloat in [20, 40, 80] {
            let success = AgentAvatarContent(name: "Build Agent", size: size,
                phase: .success(Image(uiImage: image)))
            XCTAssertNotEqual(try rendered(success),
                try rendered(AgentAvatarContent(name: "Build Agent", size: size, phase: .empty)))
            let actual = try alphaMask(success)
            let expected = try alphaMask(Circle().fill(.black).frame(width: size, height: size))
            XCTAssertEqual(actual.count, expected.count)
            XCTAssertEqual(zip(actual, expected).filter { abs(Int($0) - Int($1)) > 2 }.count, 0)
        }
    }

    private func rendered<Content: View>(_ content: Content) throws -> Data {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        return try XCTUnwrap(renderer.uiImage?.pngData())
    }

}
