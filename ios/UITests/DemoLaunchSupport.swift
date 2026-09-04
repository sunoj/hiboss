// Shared XCUIApplication launch helpers for demo-mode UI tests.
// Exports: XCUIApplication.configureDemoLaunch.
// Dependencies: XCTest.

import XCTest

extension XCUIApplication {
    /// Demo deep-link flags that must not leak across launches. Simulator
    /// `launchctl setenv HIBOSS_DEMO_SESSION` (used by some screenshot flows) persists
    /// into every later process — including XCTest — and would push the session
    /// transcript over Inbox / Resolved / Progress unless we blank the unused keys.
    private static let demoRouteKeys = [
        "HIBOSS_DEMO_OPEN",
        "HIBOSS_DEMO_NOTIFICATION_OPEN",
        "HIBOSS_DEMO_NOTIFICATION_PREVIEW",
        "HIBOSS_DEMO_SESSION",
        "HIBOSS_DEMO_RESOLVED",
        "HIBOSS_DEMO_EMPTY",
        "HIBOSS_DEMO_HISTORY_DELAY_MS",
        "HIBOSS_DEMO_MESSAGE_DELAY_MS",
        "HIBOSS_TAB",
    ]

    /// Sets `HIBOSS_DEMO=1`, clears stale route flags, then applies `extra` overrides.
    func configureDemoLaunch(_ extra: [String: String] = [:]) {
        launchEnvironment["HIBOSS_DEMO"] = "1"
        for key in Self.demoRouteKeys {
            launchEnvironment[key] = ""
        }
        for (key, value) in extra {
            launchEnvironment[key] = value
        }
    }
}
