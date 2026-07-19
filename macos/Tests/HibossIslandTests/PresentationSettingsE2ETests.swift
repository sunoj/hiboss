// End-to-end tests for macOS presentation preferences and option layout.
// Covers: persisted mode choices and complete long-text presentation.
// Dependencies: XCTest, isolated UserDefaults, AppSettings, and layout sizing.

import Foundation
import HibossKit
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
}

private struct StubTokenStore: TokenStoring {
    let token: String?

    init(token: String? = nil) {
        self.token = token
    }

    func read() throws -> String? { token }
    func write(_ token: String) throws {}
}
