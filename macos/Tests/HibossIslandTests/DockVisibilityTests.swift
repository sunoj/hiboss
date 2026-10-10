// Tests persisted Dock visibility and its AppKit activation policy mapping.
// Covers: legacy defaults, explicit choices across launches, and menu-bar independence.
// Dependencies: XCTest, AppKit, HibossKit storage keys, and isolated AppSettings.

import AppKit
import Combine
import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class DockVisibilityTests: XCTestCase {
    func testDefaultPreservesExistingPresentationAndMenuBarPolicy() {
        for mode in OptionPresentationMode.allCases {
            for showsStatusItem in [true, false] {
                let defaults = isolatedDefaults()
                defaults.set(mode.rawValue, forKey: AppConstants.Storage.presentationMode)
                defaults.set(showsStatusItem, forKey: AppConstants.Storage.showsStatusItem)
                let settings = AppSettings(defaults: defaults, keychain: DockTokenStore())
                let needsDock = mode == .window || !showsStatusItem

                XCTAssertEqual(settings.showsInDock, needsDock)
                XCTAssertEqual(
                    AppSettings.activationPolicy(showsInDock: settings.showsInDock),
                    needsDock ? .regular : .accessory
                )
            }
        }
    }

    func testPersistedPreferenceOverridesPresentationPolicyAcrossLaunches() {
        let defaults = isolatedDefaults()
        let initial = AppSettings(defaults: defaults, keychain: DockTokenStore())

        for showsInDock in [true, false] {
            initial.showsInDock = showsInDock
            initial.presentationMode = .window
            let restored = AppSettings(defaults: defaults, keychain: DockTokenStore())

            XCTAssertEqual(restored.showsInDock, showsInDock)
            XCTAssertEqual(
                AppSettings.activationPolicy(showsInDock: restored.showsInDock),
                showsInDock ? .regular : .accessory
            )
            XCTAssertTrue(initial.showsStatusItem)
            XCTAssertTrue(restored.showsStatusItem)
        }
    }

    func testPreferencePublishesActivationPolicyImmediately() {
        let settings = AppSettings(defaults: isolatedDefaults(), keychain: DockTokenStore())
        var policies: [NSApplication.ActivationPolicy] = []
        let observer = settings.$showsInDock
            .removeDuplicates()
            .map { AppSettings.activationPolicy(showsInDock: $0) }
            .sink { policies.append($0) }

        settings.showsInDock = true
        settings.showsInDock = false

        XCTAssertEqual(policies, [.accessory, .regular, .accessory])
        withExtendedLifetime(observer) {}
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "DockVisibilityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }
}

private struct DockTokenStore: TokenStoring {
    func read() throws -> String? { nil }
    func write(_ token: String) throws {}
}
