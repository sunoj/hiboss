// The demo a new user enters from onboarding: fixture data only, kept until they exit it.
// Exports: DemoSession (persisted flag, enter/exit, demo residue purge) read via `isDemoMode`.
// Dependencies: Foundation, ActivityKit, os unfair lock, shared Live Activity attributes.

import ActivityKit
import Foundation
import os

@MainActor
final class DemoSession: ObservableObject {
    static let shared = DemoSession()
    nonisolated static let activeKey = "hiboss.demo.active"
    nonisolated static let readsSuite = "ai.hiboss.demo.reads"
    /// Questionnaire draft scopes of the demo panel services.
    nonisolated static let draftPrefixes = ["native-demo-", "metric-demo.", "home-demo."]
        .map { "hiboss.questionnaire.\($0)" }

    private nonisolated static let flag = OSAllocatedUnfairLock(
        initialState: UserDefaults.standard.bool(forKey: activeKey)
    )

    /// True while a demo entered from onboarding is running; launch-flag demos never show Exit.
    @Published private(set) var isActive = DemoSession.isRuntimeActive
    /// Advances on every enter and exit, so the app rebuilds every store from scratch.
    @Published private(set) var generation = 0

    nonisolated static var isRuntimeActive: Bool { flag.withLock { $0 } }

    func enter() {
        Self.purgeStoredResidue()
        setActive(true)
    }

    /// Callers stop their demo services first; this then removes everything the demo left.
    func exit() async {
        setActive(false)
        Self.purgeStoredResidue()
        await Self.endLiveActivities()
    }

    private func setActive(_ active: Bool) {
        Self.flag.withLock { $0 = active }
        if active {
            UserDefaults.standard.set(true, forKey: Self.activeKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.activeKey)
        }
        isActive = active
        generation &+= 1
    }

    /// Session read state for a demo entered from onboarding lives in one removable suite.
    static func sessionReadDefaults() -> UserDefaults {
        UserDefaults(suiteName: readsSuite) ?? .standard
    }

    /// Demo data persists only as read state and questionnaire drafts; the demo never
    /// writes the Keychain, the shared app group or a server.
    nonisolated static func purgeStoredResidue(
        standard: UserDefaults = .standard, readsSuite: String = readsSuite
    ) {
        UserDefaults(suiteName: readsSuite)?.removePersistentDomain(forName: readsSuite)
        for key in standard.dictionaryRepresentation().keys
        where draftPrefixes.contains(where: key.hasPrefix) {
            standard.removeObject(forKey: key)
        }
    }

    /// The demo is entered only while signed out, so every running activity is demo content.
    private static func endLiveActivities() async {
        for activity in Activity<DecisionActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
