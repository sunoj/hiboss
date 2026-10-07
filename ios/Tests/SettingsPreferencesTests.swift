// Settings preference drafts survive failed saves and edits made while a response is pending.
// Exports: SettingsPreferencesTests, including wait thresholds and connection recovery wording.
// Dependencies: XCTest, HibossKit, PreferencesStore, SettingsWaitStage.

import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class SettingsPreferencesTests: XCTestCase {
    func testFailedSaveKeepsTheDraftAndRetrySavesIt() async {
        let api = ControlledPreferencesAPI()
        let store = PreferencesStore()
        await store.load(api: api)
        store.setPrivatePush(true)
        let draft = store.prefs
        await store.load(api: api)
        XCTAssertEqual(store.prefs, draft, "a refresh must not replace unsaved input")
        api.shouldFail = true
        await store.save()
        XCTAssertEqual(store.prefs, draft)
        XCTAssertTrue(store.isDirty)
        XCTAssertFalse(store.isSaving)
        guard case .failed = store.state else { return XCTFail("Expected a failed save") }
        api.shouldFail = false
        await store.save()
        XCTAssertEqual(store.prefs, draft)
        XCTAssertFalse(store.isDirty)
        XCTAssertTrue(store.didSave)
    }

    func testAnEditDuringSavingRemainsUnsavedAfterTheResponse() async {
        let api = ControlledPreferencesAPI()
        let store = PreferencesStore()
        await store.load(api: api)
        store.setPrivatePush(true)
        api.pause = true
        let save = Task { await store.save() }
        while api.continuation == nil { await Task.yield() }
        XCTAssertTrue(store.isSaving)
        store.setDecisionAlerts(false)
        let newerDraft = store.prefs
        api.continuation?.resume()
        await save.value
        XCTAssertEqual(store.prefs, newerDraft, "the earlier response must not erase a newer edit")
        XCTAssertTrue(store.isDirty)
        XCTAssertFalse(store.decisionAlerts)
        api.pause = false
        await store.save()
        XCTAssertFalse(store.isDirty)
    }

    func testWaitProgressStartsAt300MillisecondsAndEscalatesAtEightSeconds() {
        XCTAssertEqual(SettingsWaitStage.at(elapsed: .milliseconds(299)), .context)
        XCTAssertEqual(SettingsWaitStage.at(elapsed: .milliseconds(300)), .progress)
        XCTAssertEqual(SettingsWaitStage.at(elapsed: .milliseconds(7_999)), .progress)
        XCTAssertEqual(SettingsWaitStage.at(elapsed: .seconds(8)), .longWait)
    }

    func testDisconnectedDoesNotClaimThePhoneIsConnected() {
        let guidance = SettingsConnectionSummary.guidance(.disconnected, configured: true)
        XCTAssertTrue(guidance.contains("reconnect"))
        XCTAssertFalse(guidance.contains("is connected"))
    }

    func testQuietTimeUsesAModernUTCAnchorAndKeepsWallClockDigits() {
        let date = QuietTime.date(from: "22:00")
        XCTAssertEqual(QuietTime.calendar.component(.year, from: date), 2001)
        XCTAssertEqual(QuietTime.string(from: date), "22:00")
        XCTAssertEqual(QuietTime.string(from: QuietTime.date(from: "08:00")), "08:00")
    }
}

@MainActor
private final class ControlledPreferencesAPI: BossPreferencesServing {
    var shouldFail = false
    var pause = false
    var continuation: CheckedContinuation<Void, Never>?

    func fetchPreferences() async throws -> BossPreferences { BossPreferences() }

    func updatePreferences(_ preferences: BossPreferences) async throws -> BossPreferences {
        if pause { await withCheckedContinuation { continuation = $0 } }
        if shouldFail { throw URLError(.notConnectedToInternet) }
        return preferences
    }
}
