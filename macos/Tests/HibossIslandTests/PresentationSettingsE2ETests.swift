// End-to-end tests for macOS presentation preferences and option layout.
// Covers: persisted mode choices and complete long-text presentation.
// Dependencies: XCTest, isolated UserDefaults, AppSettings, and layout sizing.

import AppKit
import Foundation
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class PresentationSettingsE2ETests: XCTestCase {
    func testDefaultsToIslandModeWithVisibleMenuBarIcon() {
        let defaults = isolatedDefaults()
        let settings = AppSettings(defaults: defaults, keychain: StubTokenStore())

        XCTAssertEqual(settings.presentationMode, .island)
        XCTAssertTrue(settings.showsStatusItem)
    }

    func testRestoresWindowModeAndHiddenMenuBarIconOnNextLaunch() {
        let defaults = isolatedDefaults()
        let initial = AppSettings(defaults: defaults, keychain: StubTokenStore())

        initial.presentationMode = .window
        initial.showsStatusItem = false

        let restored = AppSettings(defaults: defaults, keychain: StubTokenStore())
        XCTAssertEqual(restored.presentationMode, .window)
        XCTAssertFalse(restored.showsStatusItem)
    }

    func testDefaultsToAnAudibleGlassAlert() {
        let settings = AppSettings(defaults: isolatedDefaults(), keychain: StubTokenStore())

        XCTAssertTrue(settings.playsSound)
        XCTAssertEqual(settings.alertSound, .glass)
    }

    func testRestoresAMutedAlertAndItsChosenSoundOnNextLaunch() {
        let defaults = isolatedDefaults()
        let initial = AppSettings(defaults: defaults, keychain: StubTokenStore())

        initial.playsSound = false
        initial.alertSound = .submarine

        let restored = AppSettings(defaults: defaults, keychain: StubTokenStore())
        XCTAssertFalse(restored.playsSound)
        XCTAssertEqual(restored.alertSound, .submarine)
    }

    func testFallsBackWhenStoredSoundIsNoLongerOffered() {
        let defaults = isolatedDefaults()
        defaults.set("RetiredSound", forKey: AppConstants.Storage.alertSound)

        let settings = AppSettings(defaults: defaults, keychain: StubTokenStore())

        XCTAssertEqual(settings.alertSound, .fallback)
    }

    func testLoadsStoredTokenAfterSettingsInitialization() async {
        let settings = AppSettings(
            defaults: isolatedDefaults(),
            keychain: StubTokenStore(token: "stored-boss-token")
        )

        XCTAssertEqual(settings.bossToken, "")
        await settings.loadToken()
        XCTAssertEqual(settings.bossToken, "stored-boss-token")
    }

    func testClosingLastWindowKeepsApplicationRunning() {
        let delegate = AppDelegate()

        XCTAssertFalse(
            delegate.applicationShouldTerminateAfterLastWindowClosed(.shared)
        )
    }

    func testLongQuestionAndOptionExpandPresentationHeight() {
        let compact = message(body: "Choose", option: "Continue")
        let long = message(
            body: String(repeating: "A detailed progress update needs wrapping. ", count: 5),
            option: String(repeating: "Continue with the audited deployment path. ", count: 3)
        )

        let compactHeight = OptionPanelLayout.expandedHeight(for: compact)
        let longHeight = OptionPanelLayout.expandedHeight(for: long)

        XCTAssertGreaterThan(longHeight, compactHeight + 80)
    }

    func testShortDecisionBodyRendersWithoutAScrollContainer() async throws {
        let message = OptionMessage(
            id: "review-757",
            body: "PR #757 review done (verdict FIX). Draft at scratchpad/review-757.md. Post it as a PR review comment, dispatch the fix round now, or hold for the response audit result?",
            agentName: "Review Agent",
            metadata: MessageMetadata(
                options: ["Post review to PR #757", "Dispatch fix round (aid)", "Hold"],
                defaultOption: "Hold"
            ),
            expiresAt: "2100-09-04T02:00:00Z",
            sessionLabel: "smart-router/perf/723-rh-fast-mode"
        )
        let store = OptionFlowStore(reconnectDelay: .seconds(60))
        store.connect(api: ScriptedBossAPI(messages: [message]))
        try await waitUntilActive(message.id, in: store)
        let height = OptionPanelLayout.expandedHeight(for: message)
        let host = NSHostingView(
            rootView: IslandView(flow: store).frame(width: AppConstants.Island.width, height: height)
        )
        host.frame = NSRect(x: 0, y: 0, width: AppConstants.Island.width, height: height)
        host.layoutSubtreeIfNeeded()

        XCTAssertFalse(containsScrollView(host))
    }

    func testDecodesMessageHistoryWithRepliesAndOptionMetadata() throws {
        let payload = """
        {
          "messages": [{
            "id": "history-message",
            "body": "Choose a cleanup path",
            "agent_name": "Build Agent",
            "direction": "agent_to_boss",
            "status": "replied",
            "priority": "normal",
            "metadata": { "options": ["Safe, recommended", "Fast"] },
            "created_at": "2026-07-15 10:00:00"
          }],
          "total": 1
        }
        """

        let response = try JSONDecoder().decode(
            HistoryResponse.self,
            from: Data(payload.utf8)
        )

        XCTAssertEqual(response.total, 1)
        XCTAssertEqual(response.messages.first?.agentName, "Build Agent")
        XCTAssertEqual(response.messages.first?.options, ["Safe, recommended", "Fast"])
    }

    private func message(body: String, option: String) -> OptionMessage {
        OptionMessage(
            id: "presentation-message",
            body: body,
            agentName: "Test Agent",
            metadata: MessageMetadata(options: [option]),
            expiresAt: nil
        )
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "PresentationSettingsE2ETests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }

    private func waitUntilActive(_ id: MessageID, in store: OptionFlowStore) async throws {
        for _ in 0..<100 {
            if store.activeMessage?.id == id { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw TestError.timeout
    }

    private func containsScrollView(_ view: NSView) -> Bool {
        view is NSScrollView || view.subviews.contains(where: containsScrollView)
    }
}

private struct StubTokenStore: TokenStoring {
    let token: String?

    init(token: String? = nil) {
        self.token = token
    }

    func read() throws -> String? { token }
    func write(_ token: String) throws {}
}
