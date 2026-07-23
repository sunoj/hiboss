// Loads and edits the boss notification preferences (routing + quiet hours).
// Exports: PreferencesStore driving the Settings routing and quiet-hours UI.
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

    private var api: HibossAPI?
    private var saved = BossPreferences()

    var isDirty: Bool { prefs != saved }

    /// Demo-harness preferences so the routing UI is exercisable without a server.
    func loadDemo() {
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
            )
        )
        prefs = sample
        saved = sample
        state = .loaded
    }

    func load(api: HibossAPI?) async {
        guard let api else { state = .unavailable; return }
        self.api = api
        if case .loading = state { return }
        state = .loading
        do {
            let loaded = try await api.fetchPreferences()
            prefs = loaded
            saved = loaded
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func save() async {
        guard let api, isDirty, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let stored = try await api.updatePreferences(prefs)
            prefs = stored
            saved = stored
            state = .loaded
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

    // MARK: Quiet hours

    var quietHours: QuietHours { prefs.quietHours ?? .defaultHours }

    func updateQuietHours(_ transform: (QuietHours) -> QuietHours) {
        prefs.quietHours = transform(quietHours)
    }
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
