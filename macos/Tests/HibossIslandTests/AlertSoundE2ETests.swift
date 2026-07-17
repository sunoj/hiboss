// End-to-end tests for the arrival alert sound.
// Covers: sounding once per surfaced question, the mute toggle, and the chosen sound.
// Dependencies: XCTest, IslandPanelController, AppSettings, and a recording player.

import Combine
import XCTest
@testable import HibossIsland

@MainActor
final class AlertSoundE2ETests: XCTestCase {
    func testSoundsOnceWhenAQuestionSurfacesAndAgainForTheNextOne() async throws {
        let first = OptionMessage.fixture(id: "first", options: ["Ship"])
        let second = OptionMessage.fixture(id: "second", options: ["Wait"])
        let (flow, settings, player) = makeController(messages: [first, second])

        try await waitUntil { flow.activeMessage?.id == first.id }
        XCTAssertEqual(player.played, [settings.alertSound])

        await flow.choose("Ship", for: first.id)
        try await waitUntil { flow.activeMessage?.id == second.id }
        XCTAssertEqual(player.played, [settings.alertSound, settings.alertSound])
    }

    func testSoundsForTheQueuedQuestionThatSurfacesBehindASkip() async throws {
        let first = OptionMessage.fixture(id: "skipped", options: ["Ship"])
        let second = OptionMessage.fixture(id: "queued", options: ["Wait"])
        let (flow, settings, player) = makeController(messages: [first, second])

        try await waitUntil { flow.activeMessage?.id == first.id }
        flow.skip()

        try await waitUntil { flow.activeMessage?.id == second.id }
        XCTAssertEqual(player.played, [settings.alertSound, settings.alertSound])
    }

    func testStaysSilentWhileTheAlertIsMuted() async throws {
        let message = OptionMessage.fixture(id: "muted", options: ["Ship"])
        let (flow, _, player) = makeController(messages: [message]) { settings in
            settings.playsSound = false
        }

        try await waitUntil { flow.activeMessage?.id == message.id }
        XCTAssertTrue(player.played.isEmpty)
    }

    func testPlaysTheChosenSoundRatherThanTheDefault() async throws {
        let message = OptionMessage.fixture(id: "chosen", options: ["Ship"])
        let (flow, _, player) = makeController(messages: [message]) { settings in
            settings.alertSound = .submarine
        }

        try await waitUntil { flow.activeMessage?.id == message.id }
        XCTAssertEqual(player.played, [.submarine])
    }

    private func makeController(
        messages: [OptionMessage],
        configure: (AppSettings) -> Void = { _ in }
    ) -> (OptionFlowStore, AppSettings, RecordingSoundPlayer) {
        let suiteName = "AlertSoundE2ETests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults, keychain: SilentTokenStore())
        configure(settings)
        let flow = OptionFlowStore(reconnectDelay: .seconds(60))
        let player = RecordingSoundPlayer()
        let controller = IslandPanelController(flow: flow, settings: settings, soundPlayer: player)
        addTeardownBlock { _ = controller }
        flow.connect(api: ScriptedBossAPI(messages: messages))
        return (flow, settings, player)
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for condition")
    }
}

private final class RecordingSoundPlayer: SoundPlaying, @unchecked Sendable {
    private(set) var played: [OptionSound] = []

    func play(_ sound: OptionSound) {
        played.append(sound)
    }
}

private struct SilentTokenStore: TokenStoring {
    func read() throws -> String? { nil }
    func write(_ token: String) throws {}
}
