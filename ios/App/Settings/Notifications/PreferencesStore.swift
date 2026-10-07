// Loads and edits the boss notification preferences (routing, quiet hours, push tiering).
// Exports: PreferencesStore driving the Settings preference editor UI.
// Dependencies: HibossKit HibossAPI/BossPreferences.

import Combine
import Foundation
import HibossKit

@MainActor
final class PreferencesStore: ObservableObject {
    enum LoadState: Equatable { case idle, loading, loaded, unavailable, failed(String) }

    @Published private(set) var prefs = BossPreferences()
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var isSaving = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var didSave = false

    private var api: (any BossPreferencesServing)?
    private var saved = BossPreferences()

    var isDirty: Bool { prefs != saved }

    /// Demo-harness preferences so the routing UI is exercisable without a server.
    func loadDemo() {
        api = DemoSettingsPreferencesAPI()
        let sample = BossPreferences(
            routing: [
                .critical: [.discord, .telegram],
                .high: [.telegram],
                .normal: [.discord],
                .low: [],
            ],
            quietHours: QuietHours(
                enabled: true, start: "22:00", end: "08:00",
                timezone: TimeZone.current.identifier,
                days: [0, 1, 2, 3, 4, 5, 6], criticalBypass: true
            ),
            push: [
                .critical: PushRule(deliver: true, sound: true, level: .timeSensitive),
                .high: PushRule(deliver: true, sound: true, level: .active),
                .normal: PushRule(deliver: true, sound: false, level: .passive),
                .low: PushRule(deliver: false, sound: false, level: .passive),
            ]
        )
        prefs = sample
        saved = sample
        state = .loaded
        hasLoaded = true
    }

    func load(api: (any BossPreferencesServing)?) async {
        guard !isDirty, !isSaving else { return }
        guard let api else { state = .unavailable; return }
        self.api = api
        if case .loading = state { return }
        state = .loading
        do {
            let loaded = try await api.fetchPreferences()
            prefs = loaded
            saved = loaded
            state = .loaded
            hasLoaded = true
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func save() async {
        guard let api, isDirty, !isSaving else { return }
        isSaving = true
        didSave = false
        let submitted = prefs
        defer { isSaving = false }
        do {
            let stored = try await api.updatePreferences(submitted)
            if prefs == submitted { prefs = stored }
            saved = stored
            state = .loaded
            didSave = true
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: Routing

    func channels(for priority: HibossKit.MessagePriority) -> Set<NotificationChannel> {
        Set(prefs.routing?[priority] ?? [])
    }

    func toggle(_ channel: NotificationChannel, for priority: HibossKit.MessagePriority) {
        var routing = prefs.routing ?? [:]
        var selected = routing[priority] ?? []
        if let index = selected.firstIndex(of: channel) {
            selected.remove(at: index)
        } else {
            selected.append(channel)
        }
        routing[priority] = selected
        prefs.routing = routing
    }

    // MARK: Push tiering

    func pushRule(for priority: HibossKit.MessagePriority) -> PushRule {
        prefs.push?[priority] ?? Self.defaultPushRule(for: priority)
    }

    func setPushRule(_ rule: PushRule, for priority: HibossKit.MessagePriority) {
        var push = prefs.push ?? [:]
        push[priority] = rule
        prefs.push = push
    }

    private static func defaultPushRule(for priority: HibossKit.MessagePriority) -> PushRule {
        switch priority {
        case .critical:
            PushRule(deliver: true, sound: true, level: .timeSensitive)
        case .high:
            PushRule(deliver: true, sound: true, level: .active)
        case .normal:
            PushRule(deliver: true, sound: false, level: .passive)
        case .low:
            PushRule(deliver: false, sound: false, level: .passive)
        }
    }

    // MARK: Quiet hours

    var quietHours: QuietHours { prefs.quietHours ?? .defaultHours }

    func updateQuietHours(_ transform: (QuietHours) -> QuietHours) {
        prefs.quietHours = transform(quietHours)
    }

    // MARK: Private notifications

    var privatePush: Bool { prefs.privatePush ?? false }

    func setPrivatePush(_ on: Bool) { prefs.privatePush = on }

    // MARK: Decision alerts

    var decisionAlerts: Bool { prefs.decisionAlerts ?? true }

    func setDecisionAlerts(_ on: Bool) { prefs.decisionAlerts = on }
}

extension QuietHours {
    static var defaultHours: QuietHours {
        QuietHours(
            enabled: false, start: "22:00", end: "08:00",
            timezone: TimeZone.current.identifier,
            days: [0, 1, 2, 3, 4, 5, 6], criticalBypass: true
        )
    }

    func with(
        enabled: Bool? = nil, start: String? = nil, end: String? = nil, criticalBypass: Bool? = nil
    ) -> QuietHours {
        QuietHours(
            enabled: enabled ?? self.enabled,
            start: start ?? self.start,
            end: end ?? self.end,
            timezone: timezone,
            days: days,
            criticalBypass: criticalBypass ?? self.criticalBypass
        )
    }
}
