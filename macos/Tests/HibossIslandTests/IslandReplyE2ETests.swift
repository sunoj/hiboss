// Island composer end to end: one controller-owned reply state, drafts keyed by message id.
// Exports: IslandReplyE2ETests over conflicts, failures, question changes and host recreation.
// Dependencies: XCTest, AppKit hosting, IslandPanelController, OutcomeScriptAPI.

import AppKit
import SwiftUI
import XCTest
import HibossKit
@testable import HibossIsland

@MainActor
final class IslandReplyE2ETests: XCTestCase {

    func testControllerInjectsOneReplyStateIntoBothPresentationRoots() {
        let suiteName = "IslandReplyE2ETests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults, keychain: NoTokenStore())
        let controller = IslandPanelController(flow: OptionFlowStore(), settings: settings)

        let island = controller.panel.contentView as? NSHostingView<IslandView>
        let window = controller.optionWindow.contentView as? NSHostingView<IslandView>

        XCTAssertTrue(island?.rootView.reply === controller.reply)
        XCTAssertTrue(window?.rootView.reply === controller.reply)
    }

    func testConflictKeepsTypedDraftAcrossNextQuestionAndHostRecreation() async throws {
        let first = OptionMessage.fixture(id: "first", options: ["Ship"])
        let second = OptionMessage.fixture(id: "second", options: ["Ship"])
        let api = OutcomeScriptAPI(questions: [], live: [first, second], steps: [.conflictUnrecorded])
        let flow = try await connected(api)
        defer { flow.disconnect() }
        try await waitForCondition { flow.activeMessage?.id == "first" }
        let reply = AttentionReplyState()
        let host = Self.host(flow, reply)
        reply.drafts["first"] = "Hold until Monday"
        let shown1 = try await Self.fieldText(host)
        XCTAssertEqual(shown1, "Hold until Monday")

        await reply.send(reply.drafts["first"] ?? "", for: "first", using: flow.answer)

        XCTAssertEqual(flow.activeMessage?.id, "second", "the answered-elsewhere question is withdrawn")
        XCTAssertEqual(reply.drafts["first"], "Hold until Monday")
        XCTAssertEqual(reply.errors["first"], .alreadyAnswered)
        XCTAssertNil(reply.errors["second"])
        let shown2 = try await Self.fieldText(host)
        XCTAssertEqual(shown2, "", "the next question never shows another's draft")

        reply.drafts["second"] = "Ship tonight"
        let recreated = Self.host(flow, reply)
        let shown3 = try await Self.fieldText(recreated)
        XCTAssertEqual(shown3, "Ship tonight")
        XCTAssertEqual(reply.drafts["first"], "Hold until Monday")
    }

    func testFailedLiveChoiceKeepsQuestionDraftAndOwnFeedback() async throws {
        let live = OptionMessage.fixture(id: "live", options: ["Ship", "Wait"])
        let api = OutcomeScriptAPI(questions: ["other"], live: [live], steps: [.fail, .accept])
        let flow = try await connected(api)
        defer { flow.disconnect() }
        try await waitForCondition { flow.activeMessage?.id == "live" }
        let reply = AttentionReplyState()
        let host = Self.host(flow, reply)
        reply.drafts["live"] = "Only after the smoke tests"

        await reply.send("Ship", for: "live", using: flow.answer)

        XCTAssertEqual(flow.activeMessage?.id, "live")
        XCTAssertEqual(flow.presentationState, .ready)
        XCTAssertEqual(reply.errors["live"], .failed("The reply was rejected."))
        let shown4 = try await Self.fieldText(host)
        XCTAssertEqual(shown4, "Only after the smoke tests")

        await reply.send("Ship", for: "other", using: flow.answer)
        XCTAssertNil(reply.errors["other"])
        XCTAssertEqual(reply.errors["live"], .failed("The reply was rejected."),
                       "another message's reply never touches the presented question's feedback")
        XCTAssertTrue(reply.submitting.isEmpty)
    }

    func testAcceptedLiveReplyClearsOnlyItsDraftAndDismissesTheQuestion() async throws {
        let live = OptionMessage.fixture(id: "live", options: ["Ship"])
        let api = OutcomeScriptAPI(questions: ["live"], live: [live], steps: [.accept])
        let flow = try await connected(api)
        defer { flow.disconnect() }
        try await waitForCondition { flow.activeMessage?.id == "live" }
        let reply = AttentionReplyState()
        reply.drafts["live"] = "Ship it"
        reply.drafts["other"] = "Unrelated"

        await reply.send("Ship it", for: "live", using: flow.answer)

        XCTAssertNil(reply.drafts["live"])
        XCTAssertNil(reply.errors["live"])
        XCTAssertEqual(reply.drafts["other"], "Unrelated")
        XCTAssertNil(flow.activeMessage)
        XCTAssertEqual(flow.presentationState, .idle, "this device's answer is not shown as answered elsewhere")
    }

    private func connected(_ api: OutcomeScriptAPI) async throws -> OptionFlowStore {
        let flow = OptionFlowStore(reconnectDelay: .seconds(60))
        flow.connect(api: api)
        try await waitForCondition { flow.historyState == .loaded }
        return flow
    }

    private static func host(_ flow: OptionFlowStore, _ reply: AttentionReplyState) -> NSHostingView<some View> {
        let height = flow.activeMessage.map { OptionPanelLayout.expandedHeight(for: $0) } ?? 320
        let host = NSHostingView(rootView: IslandView(flow: flow, reply: reply, surfaceStyle: .window)
            .frame(width: AppConstants.Island.width, height: height))
        host.frame = NSRect(x: 0, y: 0, width: AppConstants.Island.width, height: height)
        return host
    }

    /// The reply field's rendered text after SwiftUI has applied pending state.
    private static func fieldText(_ host: NSView) async throws -> String {
        try await Task.sleep(for: .milliseconds(50))
        host.layoutSubtreeIfNeeded()
        let fields = textFields(in: host)
        XCTAssertEqual(fields.count, 1, "one reply field per presented question")
        return fields.first?.stringValue ?? "<no field>"
    }

    private static func textFields(in view: NSView) -> [NSTextField] {
        view.subviews.flatMap { subview -> [NSTextField] in
            if let field = subview as? NSTextField, field.isEditable { return [field] }
            return textFields(in: subview)
        }
    }
}

private struct NoTokenStore: TokenStoring {
    func read() throws -> String? { nil }
    func write(_ token: String) throws {}
}
