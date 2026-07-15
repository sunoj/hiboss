// End-to-end tests for macOS presentation preferences and option layout.
// Covers: persisted mode choices and complete long-text presentation.
// Dependencies: XCTest, isolated UserDefaults, AppSettings, and layout sizing.

import Foundation
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
    func read() throws -> String? { nil }
    func write(_ token: String) throws {}
}
