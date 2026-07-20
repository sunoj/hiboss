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

    public init(
        api: any BossPreferencesServing,
        initialPreferences: BossPreferences = BossPreferences()
    ) {
        self.api = api
        self.preferences = initialPreferences
    }

    public func load() async {
        state = .loading
        do {
            preferences = try await api.fetchPreferences()
            state = .loaded
        } catch where Task.isCancelled {
            return
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func save() async {
        state = .saving
        do {
            preferences = try await api.updatePreferences(preferences)
            state = .loaded
        } catch where Task.isCancelled {
            return
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
