// Coverage for preference loading and saving state transitions.
// Exports: BossPreferencesStoreTests with success and failure paths.
// Dependencies: XCTest and BossPreferencesServing test doubles.

import XCTest
@testable import HibossKit

final class BossPreferencesStoreTests: XCTestCase {
    @MainActor
    func testLoadSuccessPublishesPreferences() async {
        let expected = BossPreferences(routing: [.critical: [.api]])
        let api = StubPreferencesAPI(fetchResult: .success(expected), updateResult: .success(expected))
        let store = BossPreferencesStore(api: api)

        await store.load()

        XCTAssertEqual(store.preferences, expected)
        XCTAssertEqual(store.state, .loaded)
    }

    @MainActor
    func testLoadFailurePublishesFailedState() async {
        let api = StubPreferencesAPI(fetchResult: .failure(.load), updateResult: .failure(.save))
        let store = BossPreferencesStore(api: api)

        await store.load()

        XCTAssertEqual(store.preferences, BossPreferences())
        XCTAssertEqual(store.state, .failed("Load failed."))
    }

    @MainActor
    func testLoadCancellationResetsIdleState() async {
        let api = StubPreferencesAPI(fetchResult: .cancelled, updateResult: .failure(.save))
        let store = BossPreferencesStore(api: api)

        let task = Task { await store.load() }
        await Task.yield()
        task.cancel()
        await task.value

        XCTAssertEqual(store.state, .idle)
    }

    @MainActor
    func testSaveSuccessPublishesMergedPreferences() async {
        let submitted = BossPreferences(routing: [.high: [.telegram]])
        let merged = BossPreferences(routing: [.critical: [.api], .high: [.telegram]])
        let api = StubPreferencesAPI(fetchResult: .success(submitted), updateResult: .success(merged))
        let store = BossPreferencesStore(api: api, initialPreferences: submitted)

        await store.save()

        XCTAssertEqual(store.preferences, merged)
        XCTAssertEqual(store.state, .loaded)
        let updates = await api.updates
        XCTAssertEqual(updates, [submitted])
    }

    @MainActor
    func testSaveFailurePublishesFailedState() async {
        let initial = BossPreferences(routing: [.normal: [.discord]])
        let api = StubPreferencesAPI(fetchResult: .success(initial), updateResult: .failure(.save))
        let store = BossPreferencesStore(api: api, initialPreferences: initial)

        await store.save()

        XCTAssertEqual(store.preferences, initial)
        XCTAssertEqual(store.state, .failed("Save failed."))
    }

    @MainActor
    func testSaveCancellationResetsIdleState() async {
        let initial = BossPreferences(routing: [.normal: [.discord]])
        let api = StubPreferencesAPI(fetchResult: .failure(.load), updateResult: .cancelled)
        let store = BossPreferencesStore(api: api, initialPreferences: initial)

        let task = Task { await store.save() }
        await Task.yield()
        task.cancel()
        await task.value

        XCTAssertEqual(store.preferences, initial)
        XCTAssertEqual(store.state, .idle)
    }
}

private enum StubPreferenceResult: Sendable {
    case success(BossPreferences)
    case failure(StubPreferenceError)
    case cancelled
}

private enum StubPreferenceError: LocalizedError, Sendable {
    case load
    case save

    var errorDescription: String? {
        switch self {
        case .load: "Load failed."
        case .save: "Save failed."
        }
    }
}

private actor StubPreferencesAPI: BossPreferencesServing {
    private let fetchResult: StubPreferenceResult
    private let updateResult: StubPreferenceResult
    private(set) var updates: [BossPreferences] = []

    init(fetchResult: StubPreferenceResult, updateResult: StubPreferenceResult) {
        self.fetchResult = fetchResult
        self.updateResult = updateResult
    }

    func fetchPreferences() async throws -> BossPreferences {
        switch fetchResult {
        case let .success(preferences): return preferences
        case let .failure(error): throw error
        case .cancelled:
            try await Task.sleep(nanoseconds: 1_000_000_000)
            return BossPreferences()
        }
    }

    func updatePreferences(_ preferences: BossPreferences) async throws -> BossPreferences {
        updates.append(preferences)
        switch updateResult {
        case let .success(preferences): return preferences
        case let .failure(error): throw error
        case .cancelled:
            try await Task.sleep(nanoseconds: 1_000_000_000)
            return preferences
        }
    }
}
