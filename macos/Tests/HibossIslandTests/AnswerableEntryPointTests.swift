// Verifies history and notification replies against the loaded required-input list.
// Exports: AnswerableEntryPointTests covering unknown, retired, and text-only decisions.
// Dependencies: XCTest, native SwiftUI hosting, OverviewStore, and notification detail.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class AnswerableEntryPointTests: XCTestCase {
    func testHistoryOnlyDecisionChecksThenClosesAndPreservesRecordedOutcome() {
        let question = question()
        let thread = MessageThread(message: question)
        let loading = snapshot(question, loaded: false, open: true).answerability
        XCTAssertEqual(loading.state(for: question.id), .checking)
        XCTAssertFalse(loading.permitsReply(to: question))
        let open = snapshot(question, loaded: true, open: true).answerability
        XCTAssertTrue(open.permitsReply(to: question))
        XCTAssertEqual(open.outcome(for: thread, at: .now), .open)
        let closed = snapshot(question, loaded: true, open: false).answerability
        XCTAssertEqual(closed.state(for: question.id), .closed)
        XCTAssertFalse(closed.permitsReply(to: question))
        XCTAssertEqual(closed.outcome(for: thread, at: .now), .none)
        let answer = HistoryMessage(id: "answer", body: "Ship", direction: "boss_to_agent",
            status: "sent", priority: "normal", replyTo: question.id.rawValue,
            metadata: MessageMetadata(options: [], source: "ios"), createdAt: AttentionTestSupport.iso(.now))
        XCTAssertEqual(closed.outcome(for: MessageThread(message: question, replies: [answer]), at: .now),
            .chosen(option: "Ship", source: "ios"))
    }

    func testAllMessagesAndNotificationDetailOnlyExposeComposerForLoadedMember() async throws {
        for textOnly in [false, true] {
            let question = question(textOnly: textOnly)
            for (loaded, open) in [(false, true), (true, true), (true, false)] {
                let answerability = snapshot(question, loaded: loaded, open: open).answerability
                let reply = AttentionReplyState()
                reply.drafts[question.id] = "Review first"
                let views = [
                    AnyView(HistoryThreadRow(thread: MessageThread(message: question),
                        answerability: answerability, reply: reply, isExpanded: .constant(true),
                        isSearching: false, onCollapse: {}, onChoose: { _ in nil })),
                    AnyView(HistoryMessageDetail(message: question, reply: reply,
                        answerability: answerability, onChoose: { _ in nil }))
                ]
                for view in views {
                    let host = NSHostingView(rootView: view)
                    let window = show(host)
                    defer { window.close() }
                    try await waitForCondition { host.fittingSize.height > 0 }
                    host.layoutSubtreeIfNeeded()
                    XCTAssertEqual(fields(host).contains(where: \.isEnabled), loaded && open,
                        "Composer membership: loaded=\(loaded), open=\(open), textOnly=\(textOnly)")
                }
            }
        }
    }

    func testNotificationCallbackRechecksCurrentListBeforeSendingAndKeepsDraft() async throws {
        let question = question()
        let overview = OverviewStore()
        overview.update(history: [], live: nil, requiredInputs: [question], requiredInputLoaded: true)
        let reply = AttentionReplyState()
        reply.drafts[question.id] = "Review first"
        var receipts: [RecordedReply] = []
        let view = NotificationMessageDetail(messageID: "stale-id", settings: settings(), reply: reply,
            overview: overview, onReply: { text, id in
                receipts.append(RecordedReply(messageID: id, choice: text))
                return nil
            })
        let detail = view.loadedDetail(question)
        overview.update(history: [], live: nil, requiredInputLoaded: true)
        await reply.send("Review first", for: question.id) { text, _ in await detail.onChoose(text) }
        XCTAssertTrue(receipts.isEmpty)
        XCTAssertEqual(reply.drafts[question.id], "Review first")
        XCTAssertEqual(reply.errors[question.id], .alreadyResolved)
        overview.update(history: [], live: nil, requiredInputs: [question], requiredInputLoaded: true)
        let accepted = await detail.onChoose("Ship")
        XCTAssertNil(accepted)
        XCTAssertEqual(receipts, [RecordedReply(messageID: question.id, choice: "Ship")])
    }

    func testLoadingMenuBarAndSessionTargetWaitForRequiredInputs() {
        let question = question()
        let ordinary = HistoryMessage(id: "ordinary", body: "Build finished", direction: "agent_to_boss",
            status: "delivered", priority: "normal", createdAt: AttentionTestSupport.iso(.now),
            sessionId: "session")
        let snapshot = OverviewSnapshot(history: [ordinary, question], live: nil, now: .now)
        let context = SessionContext(id: "session", snapshot: snapshot, inventory: [])
        XCTAssertNil(context.newestAgentMessage)
        XCTAssertTrue(context.replyTargets.isEmpty)
        let button = NSButton()
        AppIdentity.configure(button, count: snapshot.answerability.isLoaded ? 0 : nil)
        XCTAssertEqual(button.accessibilityLabel(), L("Loading"))
        AppIdentity.configure(button, count: 0)
        XCTAssertEqual(button.accessibilityLabel(), L("HiBoss · \(0) open decisions"))
    }

    private func question(textOnly: Bool = false) -> HistoryMessage {
        HistoryMessage(id: "question", body: "Ship?", direction: "agent_to_boss", status: "delivered",
            priority: "normal", mode: textOnly ? "blocking" : nil,
            metadata: MessageMetadata(options: textOnly ? [] : ["Ship", "Hold"]),
            createdAt: AttentionTestSupport.iso(.now), sessionId: "session")
    }

    func testDefaultAloneDoesNotGateOrdinaryReplyAsADecision() {
        let message = AttentionTestSupport.ask(id: "default-only", options: [], defaultOption: "Hold")
        XCTAssertFalse(message.isDecision)
        let answerability = snapshot(message, loaded: true, open: false).answerability
        XCTAssertTrue(answerability.permitsReply(to: message))
    }

    private func snapshot(_ question: HistoryMessage, loaded: Bool, open: Bool) -> OverviewSnapshot {
        OverviewSnapshot(history: [question], live: nil, now: .now,
            requiredInputs: open ? [question] : [], requiredInputLoaded: loaded)
    }

    private func fields(_ view: NSView) -> [NSTextField] {
        view.subviews.flatMap { ($0 as? NSTextField).map { [$0] } ?? fields($0) }.filter(\.isEditable)
    }

    private func show(_ host: NSView) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 600, height: 500),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func settings() -> AppSettings {
        let suite = "AnswerableEntryPointTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return AppSettings(defaults: defaults)
    }
}
