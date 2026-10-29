// Opt-in Settings survey, skipped in ordinary tiers because each pane opens a desktop window.
// Exports: PerfSurveySettingsTests with inert preference and notification services.
// Dependencies: the real SettingsScene shell and its default-preserving initialPane seam.

import AppKit
import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class PerfSurveySettingsTests: XCTestCase {
    func testSettingsPanes() async throws {
        try PerfSurveyMetrics.enabled()
        for pane in SettingsPane.allCases {
            let label = "Settings " + pane.rawValue
            guard PerfSurveyMetrics.accepts(label) else { continue }
            let settings = PerfSurveyFixtures.settings()
            let preferences = BossPreferencesStore(api: PerfSurveyPreferences())
            let defaults = UserDefaults(suiteName: "PerfSurveyNotifications")!
            defer { defaults.removePersistentDomain(forName: "PerfSurveyNotifications") }
            let notifications = MessageNotificationStore(center: PerfSurveyNotificationCenter(),
                defaults: defaults)
            let flow = OptionFlowStore()
            let window = try PerfSurveyFixtures.window(SettingsScene(settings: settings,
                flow: flow,
                preferencesStore: preferences, notifications: notifications,
                initialPane: pane), settings: true)
            defer {
                PerfSurveyFixtures.close(window)
                flow.disconnect()
            }
            try await PerfSurveyMetrics.measure(label, size: "local / unpaired", window: window,
                update: { settings.deviceLabel = "Survey Mac" },
                interact: { settings.playsSound.toggle() })
        }
    }
}

private actor PerfSurveyPreferences: BossPreferencesServing {
    func fetchPreferences() async throws -> BossPreferences { BossPreferences() }
    func updatePreferences(_ preferences: BossPreferences) async throws -> BossPreferences { preferences }
}

@MainActor
private final class PerfSurveyNotificationCenter: MessageNotificationCenter {
    var isEnabled = false
    func authorization() async -> MessageNotificationAuthorization { .denied }
    func requestAuthorization() async throws {}
    func post(_ notice: MessageNotice) async throws {}
}
