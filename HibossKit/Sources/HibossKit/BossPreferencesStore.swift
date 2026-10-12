// Coordinates loading and saving editable boss notification preferences.
// Exports: BossPreferencesStore, BossPreferencesState, and BossPreferencesServing.
// Dependencies: Combine observation and BossPreferences domain contracts.

import Combine
import Foundation

public protocol BossPreferencesServing: Sendable {
    func fetchPreferences() async throws -> BossPreferences
    func updatePreferences(_ preferences: BossPreferences) async throws -> BossPreferences
}

public enum BossPreferencesState: Equatable {
    case idle
    case loading
    case loaded
    case saving
    case failed(String)
}

@MainActor
public final class BossPreferencesStore: ObservableObject {
    @Published public var preferences: BossPreferences
    @Published public private(set) var state: BossPreferencesState = .idle

    private let api: any BossPreferencesServing
    private var authorizationObservation: AnyCancellable?
    private var generation = 0
    @Published public private(set) var authorizationRejected = false

    public init(
        api: any BossPreferencesServing,
        initialPreferences: BossPreferences = BossPreferences()
    ) {
        self.api = api
        self.preferences = initialPreferences
        authorizationObservation = AccountAuthorization.shared.observe { [weak self] error in
            self?.generation += 1
            self?.authorizationRejected = true
            self?.preferences = BossPreferences()
            self?.state = .failed(error.localizedDescription)
        }
    }

    public func load() async {
        guard !authorizationRejected || !AccountAuthorization.shared.hasRejectedAccount else { return }
        authorizationRejected = false
        let version = generation
        state = .loading
        do {
            let loaded = try await api.fetchPreferences()
            guard version == generation else { return }
            preferences = loaded
            state = .loaded
        } catch where Task.isCancelled {
            guard version == generation else { return }
            state = .idle
            return
        } catch {
            guard version == generation else { return }
            if AccountAuthorization.shared.reject(error) { return }
            state = .failed(error.localizedDescription)
        }
    }

    public func save() async {
        guard !authorizationRejected || !AccountAuthorization.shared.hasRejectedAccount else { return }
        authorizationRejected = false
        let version = generation
        state = .saving
        do {
            let loaded = try await api.updatePreferences(preferences)
            guard version == generation else { return }
            preferences = loaded
            state = .loaded
        } catch where Task.isCancelled {
            guard version == generation else { return }
            state = .idle
            return
        } catch {
            guard version == generation else { return }
            if AccountAuthorization.shared.reject(error) { return }
            state = .failed(error.localizedDescription)
        }
    }
}
