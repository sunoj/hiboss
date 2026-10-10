// Exercises reply targeting, draft pinning, and rendered target labels in native windows.
// Exports: SessionComposerTargetTests; optional light/dark composer PNG evidence.
// Dependencies: XCTest, SwiftUI, AppKit, Vision, and production session components.

import AppKit
import HibossKit
import SwiftUI
import Vision
import XCTest
@testable import HibossIsland

@MainActor
final class SessionComposerTargetTests: XCTestCase {
    private let now = AttentionTestSupport.now

    func testOrdinaryTargetUsesOnlyTheFirstLineAndDecisionUsesTheQuestion() throws {
        let ordinary = message("ordinary", body: "Build finished\nAll checks passed")
        let question = message("question", body: "Which route should we use?", options: ["A", "B"])
        let context = context([ordinary, question], requiredInputs: [question])
        XCTAssertEqual(context.replyTargetLabel(for: ordinary), L("Replying to: \("Build finished")"))
        XCTAssertEqual(context.replyTargetLabel(for: question),
            L("Custom answer to: \("Which route should we use?")"))
    }

    func testDraftKeepsItsTargetUntilExplicitlySwitchedOrCleared() throws {
        let old = message("old", body: "Review the build", at: -60)
        let new = message("new", body: "Review the release")
        var target = SessionReplyTarget()
        target.edit("My draft", for: old)
        let updated = context([old, new])
        XCTAssertEqual(target.message(in: updated)?.id, old.id)
        XCTAssertEqual(target.newerMessage(in: updated)?.id, new.id)
        target.edit("New draft", for: new)
        XCTAssertEqual(target.message(in: updated)?.id, new.id)
        XCTAssertNil(target.newerMessage(in: updated))
        target.clearIfEmpty(drafts: [:])
        XCTAssertNil(target.pinnedID)
        XCTAssertEqual(target.message(in: updated)?.id, new.id)
    }

    func testResolvedOrHistoryOnlyDecisionsNeverBecomeTargetsEvenWhenPinned() {
        let ordinary = message("ordinary", body: "Build finished", at: -60)
        for status in ["replied", "expired", "resolved", "delivered"] {
            let question = message("question", body: "Ship?", options: ["Ship"], status: status)
            let updated = context([ordinary, question])
            XCTAssertEqual(updated.newestAgentMessage?.id, ordinary.id)
            XCTAssertNil(context([question]).newestAgentMessage)
            var target = SessionReplyTarget()
            target.edit("Draft answer", for: question)
            XCTAssertNil(target.message(in: updated))
        }
    }

    func testTextOnlyOpenDecisionIsEligibleButRetiredQuestionIsNot() {
        let question = message("text", body: "Explain the rollback", mode: "blocking")
        XCTAssertNil(context([question]).newestAgentMessage)
        XCTAssertEqual(context([question], requiredInputs: [question]).newestAgentMessage?.id, question.id)
    }

    func testRetargetMovesDraftAndDiscardRemovesOnlyPinnedDraft() {
        let old = message("old", body: "Review the build", at: -60)
        let new = message("new", body: "Review the release")
        var target = SessionReplyTarget()
        var drafts: [MessageID: String] = [old.id: "Investigate first", "unrelated": "Keep this"]
        target.edit(drafts[old.id] ?? "", for: old)
        target.retarget(to: new, drafts: &drafts)
        XCTAssertEqual(target.pinnedID, new.id)
        XCTAssertEqual(drafts[new.id], "Investigate first")
        XCTAssertNil(drafts[old.id], "The old inspector must not resurrect a transferred draft")
        target.discard(drafts: &drafts)
        XCTAssertNil(target.pinnedID)
        XCTAssertNil(drafts[new.id])
        XCTAssertEqual(drafts["unrelated"], "Keep this")
    }

    func testResolvedPinnedTargetKeepsVisibleDraftAndOffersRetargetAndDiscard() async throws {
        let old = message("old", body: "Ship?", options: ["Ship"])
        let new = message("new", body: "Review the release", at: 60)
        let reply = AttentionReplyState()
        reply.drafts[old.id] = "Investigate first"
        let host = NSHostingView(rootView: SessionComposer(context: context([old], requiredInputs: [old]),
            reply: reply, onChoose: { _, _ in nil }))
        let window = show(host, scheme: .light)
        window.setContentSize(NSSize(width: 600, height: 260))
        defer { window.close() }
        try await waitForCondition { self.fields(host).first?.stringValue == "Investigate first" }
        host.rootView = SessionComposer(context: context([old, new]), reply: reply, onChoose: { _, _ in nil })
        try await waitForCondition { self.fields(host).first?.isEnabled == false }
        XCTAssertEqual(fields(host).first?.stringValue, "Investigate first")
        let labels = try recognize(host).map(\.text)
        XCTAssertTrue(labels.contains { $0.contains("Discard") }, "\(labels)")
        XCTAssertTrue(labels.contains { $0.contains("Reply to the newer message") }, "\(labels)")
        XCTAssertFalse(labels.contains { $0.contains("No eligible agent message") })
    }

    func testTargetLabelsRenderAboveTheFieldInBothAppearances() async throws {
        let ordinary = message("ordinary", body: "Build finished\nAll checks passed")
        let question = message("question", body: "Which route should we use?", options: ["A", "B"])
        for scheme in [ColorScheme.light, .dark] {
            for (name, value, expected) in [
                ("ordinary", context([ordinary]), "Replying to: Build finished"),
                ("decision", context([question], requiredInputs: [question]),
                    "Custom answer to: Which route should we use?"),
                ("disabled", context([question]), "No eligible agent message to reply to in this session.")
            ] {
                let host = NSHostingView(rootView: SessionComposer(context: value,
                    reply: AttentionReplyState(), onChoose: { _, _ in nil })
                    .environment(\.colorScheme, scheme))
                let window = show(host, scheme: scheme)
                defer { window.close() }
                try await waitForCondition { !self.fields(host).isEmpty }
                let labels = try recognize(host)
                let label = try XCTUnwrap(labels.first { $0.text == expected }, "\(labels)")
                let editor = try XCTUnwrap(fields(host).first)
                XCTAssertEqual(editor.isEnabled, name != "disabled")
                let frame = editor.convert(editor.bounds, to: host)
                let labelY = (host.isFlipped ? 1 - label.bounds.midY : label.bounds.midY) * host.bounds.height
                if host.isFlipped { XCTAssertLessThan(labelY, frame.minY) }
                else { XCTAssertGreaterThan(labelY, frame.maxY) }
                try write(host, name: "session-composer-\(name)-\(scheme == .light ? "light" : "dark")")
            }
        }
    }

    func testTypingThenReceivingNewMessageKeepsRenderedTargetAndSendReceipt() async throws {
        let old = message("old", body: "Review the build", at: -60)
        let new = message("new", body: "Review the release")
        let reply = AttentionReplyState()
        var receipt: RecordedReply?
        let send: (String, MessageID) async -> ReplyFeedback? = { text, id in
            receipt = RecordedReply(messageID: id, choice: text)
            return nil
        }
        let host = NSHostingView(rootView: SessionComposer(context: context([old]), reply: reply,
            onChoose: send))
        let window = show(host, scheme: .light)
        defer { window.close() }
        try await waitForCondition { !self.fields(host).isEmpty }
        let field = try XCTUnwrap(fields(host).first)
        XCTAssertTrue(window.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.insertText("Investigate first", replacementRange: editor.selectedRange())
        try await waitForCondition { reply.drafts[old.id] == "Investigate first" }
        host.rootView = SessionComposer(context: context([old, new]), reply: reply, onChoose: send)
        try await waitForCondition {
            (try? self.recognize(host).contains { $0.text.contains("Reply to the newer message") }) == true
        }
        let labels = try recognize(host).map(\.text)
        XCTAssertTrue(labels.contains("Replying to: Review the build"), "\(labels)")
        XCTAssertFalse(labels.contains("Replying to: Review the release"))
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: .command, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        try await waitForCondition { window.performKeyEquivalent(with: event) }
        try await waitForCondition { receipt != nil }
        XCTAssertEqual(receipt, RecordedReply(messageID: old.id, choice: "Investigate first"))
    }

    private func context(_ history: [HistoryMessage], requiredInputs: [HistoryMessage] = [])
        -> SessionContext {
        SessionContext(id: "session", snapshot: OverviewSnapshot(history: history, live: nil, now: now,
            requiredInputs: requiredInputs, requiredInputLoaded: true), inventory: [])
    }

    private func message(_ id: MessageID, body: String, at seconds: TimeInterval = 0,
                         options: [String] = [], status: String = "delivered", mode: String? = nil)
        -> HistoryMessage {
        HistoryMessage(id: id, body: body, agentName: "Agent", direction: "agent_to_boss",
            status: status, priority: "normal", mode: mode, metadata: MessageMetadata(options: options),
            createdAt: AttentionTestSupport.iso(now.addingTimeInterval(seconds)), sessionId: "session")
    }

    private func fields(_ host: NSView) -> [NSTextField] {
        host.subviews.flatMap { view in
            (view as? NSTextField).map { [$0] } ?? fields(view)
        }.filter(\.isEditable)
    }

    private func show(_ host: NSView, scheme: ColorScheme) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 600, height: 190),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func bitmap(_ host: NSView) throws -> NSBitmapImageRep {
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    private func recognize(_ host: NSView) throws -> [(text: String, bounds: CGRect)] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap(host).cgImage)).perform([request])
        return (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map { ($0.string, observation.boundingBox) }
        }
    }

    private func write(_ host: NSView, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["HIBOSS_V4_SNAPSHOTS"] else { return }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let png = try XCTUnwrap(bitmap(host).representation(using: .png, properties: [:]))
        try png.write(to: url.appendingPathComponent("\(name).png"))
    }
}
