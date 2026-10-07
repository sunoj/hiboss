// Shared XCUIApplication launch helpers for demo-mode UI tests.
// Exports: XCUIApplication.configureDemoLaunch, launchConfiguredDemo and pullToRefresh.
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
        "HIBOSS_DEMO_PANEL_OPEN",
        "HIBOSS_DEMO_JOIN_REQUEST",
        "HIBOSS_DEMO_OPTION_MEDIA",
        "HIBOSS_DEMO_EMPTY",
        "HIBOSS_DEMO_ONBOARDING",
        "HIBOSS_DEMO_CONNECTION",
        "HIBOSS_DEMO_SESSIONS_EMPTY",
        "HIBOSS_DEMO_TEXT_ASK",
        "HIBOSS_DEMO_STABLE_DEADLINES",
        "HIBOSS_PANELS_DEMO",
        "HIBOSS_DEMO_HISTORY_DELAY_MS",
        "HIBOSS_DEMO_MESSAGE_DELAY_MS",
        "HIBOSS_DEMO_REFRESH_FAILS",
        "HIBOSS_DEMO_REPLY_DELAY_MS",
        "HIBOSS_DEMO_REQUESTS_DELAY_MS",
        "HIBOSS_DEMO_REQUESTS_READY_DELAY_MS",
        "HIBOSS_DEMO_REQUESTS_STREAM",
        "HIBOSS_DEMO_PANELS_DELAY_MS",
        "HIBOSS_DEMO_QUESTIONNAIRES_DELAY_MS",
        "HIBOSS_DEMO_TRANSCRIPT_DELAY_MS",
        "HIBOSS_DEMO_TRANSCRIPT_CONNECTION_DELAY_MS",
        "HIBOSS_DEMO_PROGRESS_DELAY_MS",
        "HIBOSS_DEMO_PROGRESS_MORE_DELAY_MS",
        "HIBOSS_DEMO_LIKE_DELAY_MS",
        "HIBOSS_DEMO_MEDIA_DELAY_MS",
        "HIBOSS_DEMO_REPLY_FAILS",
        "HIBOSS_DEMO_NATIVE_PANEL",
        "HIBOSS_DEMO_QUESTIONS_DELAY_MS",
        "HIBOSS_DEMO_SUBMISSION_DELAY_MS",
        "HIBOSS_DEMO_RECOVERY_DELAY_MS",
        "HIBOSS_DEMO_PREFERENCE_DELAY_MS",
        "HIBOSS_DEMO_WEB_DELAY_MS",
        "HIBOSS_DEMO_VIDEO_DELAY_MS",
        "HIBOSS_DEMO_CONNECT_DELAY_MS",
        "HIBOSS_DEMO_RESTORE_DELAY_MS",
        "HIBOSS_DEMO_TRANSCRIPT_EARLIER_DELAY_MS",
        "HIBOSS_DEMO_PAIRING_DELAY_MS",
        "HIBOSS_DEMO_PAIRING_POLL_DELAY_MS",
        "HIBOSS_DEMO_DEVICES_DELAY_MS",
        "HIBOSS_DEMO_DEVICE_ACTION_DELAY_MS",
        "HIBOSS_DEMO_SIGNIN_DELAY_MS",
        "HIBOSS_DEMO_SIGNIN_ACTION_DELAY_MS",
        "HIBOSS_DEMO_REFRESH_DELAY_MS",
        "HIBOSS_DEMO_ACTIVITY",
        "HIBOSS_DEMO_PREFERENCES_DELAY_MS",
        "HIBOSS_DEMO_PREFERENCES_SAVE_DELAY_MS",
        "HIBOSS_DEMO_PUSH_DELAY_MS",
        "HIBOSS_DEMO_CAMERA_DELAY_MS",
        "HIBOSS_DEMO_PANEL_FRESHNESS",
        "HIBOSS_DEMO_PAIRING_TTL",
        "HIBOSS_DEMO_SIGNIN_SCAN",
        "HIBOSS_DEMO_SETTINGS_DELAY_MS",
        "HIBOSS_DEMO_SETTINGS_DELAY_OPERATION",
        "HIBOSS_DEMO_SETTINGS_FAILURE",
        "HIBOSS_DEMO_REQUESTS_EMPTY",
        "HIBOSS_DEMO_PREFERENCES_DELAY_MS",
        "HIBOSS_DEMO_PREFERENCES_FAIL",
        "HIBOSS_TAB",
    ]

    /// Sets `HIBOSS_DEMO=1`, clears stale route flags, then applies `extra` overrides.
    func configureDemoLaunch(_ extra: [String: String] = [:]) {
        launchEnvironment["HIBOSS_DEMO"] = "1"
        for key in Self.demoRouteKeys {
            launchEnvironment[key] = ""
        }
        launchEnvironment["HIBOSS_DEMO_STABLE_DEADLINES"] = "1"
        for (key, value) in extra {
            launchEnvironment[key] = value
        }
    }

    /// A simulator cold launch can omit its injected environment; retry only when
    /// the captured onboarding field proves that the demo never started.
    func launchConfiguredDemo() {
        launch()
        if textFields["server-url-field"].waitForExistence(timeout: 1) {
            XCTContext.runActivity(named: "relaunch: first launch lost its demo environment") { _ in }
            terminate()
            launch()
        }
    }
}

/// A slow drag from the top of the content, which a quick `swipeDown()` does not reliably make.
func pullToRefresh(_ app: XCUIApplication) {
    let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
    start.press(
        forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
}
