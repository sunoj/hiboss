// Session decisions keep their text selectable. Today still opens from the summary button.
// Exports: DecisionCopyTests.
// Dependencies: AppKit, SwiftUI, and the production decision card.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class DecisionCopyTests: XCTestCase {
    func testSessionDecisionBodyIsSelectableText() async throws {
        let nodes = try await nodes(sessionRow())
        XCTAssertTrue(nodes.contains { $0.role == "AXStaticText" && $0.label.contains(Self.command) },
            "\(nodes)")
        XCTAssertTrue(nodes.contains { $0.role == "AXStaticText" && $0.label == "Run this exactly." },
            "\(nodes)")
    }

    func testTodayDecisionSummaryStaysAButton() async throws {
        let nodes = try await nodes(todayCard())
        XCTAssertFalse(nodes.contains { $0.label.contains(Self.command) }, "\(nodes)")
    }

    private func sessionRow() -> some View {
        let message = Self.message
        let item = AttentionItem(message: message, group: .priority)
        return HistoryThreadRow(thread: MessageThread(message: message),
            decision: item, usesV4: true,
            answerability: AnswerableDecisions(isLoaded: true, openIDs: [message.id]),
            reply: AttentionReplyState(), isExpanded: .constant(true), isSearching: false,
            onCollapse: {}, onChoose: { _ in nil })
            .frame(width: 640)
    }

    private func todayCard() -> some View {
        TodayDecisionCard(item: AttentionItem(message: Self.message, group: .priority),
            now: .now, isSubmitting: false, error: nil,
            onSelect: {}, onChoose: { _ in })
            .frame(width: 640)
    }

    private func nodes<V: View>(_ view: V) async throws -> [AccessNode] {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 520)
        let window = NSWindow(contentRect: NSRect(x: -3200, y: -3200, width: 640, height: 520),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.contentView = host
        window.orderBack(nil)
        defer { window.orderOut(nil); window.close() }
        try await Task.sleep(for: .milliseconds(400))
        host.layoutSubtreeIfNeeded()
        return collect(view: host)
    }

    private func collect(view: NSView) -> [AccessNode] {
        var found = [AccessNode(role: view.accessibilityRole()?.rawValue ?? "", label: text(of: view))]
        found += view.subviews.flatMap { collect(view: $0) }
        return found
    }

    private func text(of view: NSView) -> String {
        if let label = view.accessibilityLabel(), !label.isEmpty { return label }
        return view.accessibilityValue() as? String ?? ""
    }

    private static let command = "railway variable set STRIPE_SECRET"

    private static let message = HistoryMessage(
        id: "copy", body: "Stripe keys", direction: "agent_to_boss", status: "delivered",
        priority: "normal", mode: "blocking",
        metadata: MessageMetadata(options: ["Done", "Later"], content: """
        Run this exactly.

        ```
        \(command)
        ```
        """),
        createdAt: AttentionTestSupport.iso(.now), sessionId: "session")
}

private struct AccessNode: Equatable {
    let role: String
    let label: String
}
