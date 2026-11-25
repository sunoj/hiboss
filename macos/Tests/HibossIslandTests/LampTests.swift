// USB status lamp: signal rules, arrival flashes, controller commands, and the tty write.
// Exports: LampSignalTests, LampControllerTests, USBLampPortTests (logic-only, no windows).
// Dependencies: XCTest, Darwin openpty, HibossKit, AttentionTestSupport fixtures.

import Combine
import Darwin
import HibossKit
@testable import HibossIsland
import XCTest

private let now = AttentionTestSupport.now

private func ask(_ id: String, priority: String = "normal", expiresIn: TimeInterval? = nil,
                 age: TimeInterval = 60) -> HistoryMessage {
    AttentionTestSupport.ask(id: MessageID(rawValue: id), priority: priority, options: ["Yes", "No"],
        expiresAt: expiresIn.map { AttentionTestSupport.iso(now.addingTimeInterval($0)) },
        createdAt: AttentionTestSupport.iso(now.addingTimeInterval(-age)))
}

private func snapshot(_ inputs: [HistoryMessage], history: [HistoryMessage] = [],
                      loaded: Bool = true) -> OverviewSnapshot {
    OverviewSnapshot(history: history, live: nil, now: now, requiredInputs: inputs,
        requiredInputLoaded: loaded)
}

private func signal(_ snapshot: OverviewSnapshot, _ preferences: BossPreferences = BossPreferences())
    -> LampSignal {
    LampSignal.signal(decisions: snapshot.today.decisions, loaded: snapshot.answerability.isLoaded,
        preferences: preferences, now: now)
}

final class LampSignalTests: XCTestCase {
    func testOpenDecisionBlinksBlueAndNearExpiryBlinksRed() {
        XCTAssertEqual(signal(snapshot([])), .off)
        XCTAssertEqual(signal(snapshot([ask("a")], loaded: false)), .off)
        XCTAssertEqual(signal(snapshot([ask("a", expiresIn: 600)])), .waiting)
        XCTAssertEqual(signal(snapshot([ask("a", expiresIn: 600), ask("b", expiresIn: 120)])), .expiring)
        XCTAssertEqual(LampSignal.waiting.command, "show 0 0 100 blink 1000")
        XCTAssertEqual(LampSignal.expiring.command, "show 100 0 0 blink 400")
    }

    func testQuietHoursHoldNormalDecisionsButNotUrgentOnes() {
        let quiet = BossPreferences(quietHours: QuietHours(enabled: true, start: "00:00", end: "23:59",
            timezone: "UTC", days: [], criticalBypass: true))
        XCTAssertEqual(signal(snapshot([ask("a")]), quiet), .off)
        XCTAssertEqual(signal(snapshot([ask("a", priority: "high")]), quiet), .waiting)
    }

    func testOnlyAFreshUnseenAgentMessageIsAnArrival() {
        var arrivals = LampArrivals()
        XCTAssertFalse(arrivals.hasArrival(in: [ask("old", age: 3600)], now: now))
        XCTAssertTrue(arrivals.hasArrival(in: [ask("new", age: 5), ask("old", age: 3600)], now: now))
        XCTAssertFalse(arrivals.hasArrival(in: [ask("new", age: 5)], now: now))
    }
}

private final class RecordingPort: LampPortWriting, @unchecked Sendable {
    var lines: [String] = []
    func send(_ line: String) { lines.append(line) }
    func drain() {}
}

@MainActor
final class LampControllerTests: XCTestCase {
    func testSendsSignalChangesFlashesArrivalsAndGoesDarkOnStop() {
        let port = RecordingPort()
        let snapshots = PassthroughSubject<OverviewSnapshot, Never>()
        let controller = LampController(port: port, now: { now })
        controller.start(snapshots: snapshots.eraseToAnyPublisher(),
            preferences: Just(BossPreferences()).eraseToAnyPublisher())

        snapshots.send(snapshot([], history: [ask("old", age: 3600)]))
        XCTAssertEqual(port.lines, ["off"])
        let incoming = ask("new", age: 5)
        snapshots.send(snapshot([incoming], history: [incoming]))
        XCTAssertEqual(port.lines, ["off", "show 0 0 100 blink 1000", "flash 0 100 0 800"])
        snapshots.send(snapshot([incoming], history: [incoming]))
        XCTAssertEqual(port.lines.count, 3, "an unchanged snapshot sends nothing")
        controller.refresh()
        XCTAssertEqual(port.lines.last, "show 0 0 100 blink 1000")
        controller.stop()
        XCTAssertEqual(port.lines.last, "off")
    }
}

final class USBLampPortTests: XCTestCase {
    func testWritesOneLineToATerminalDevice() throws {
        var controller: Int32 = -1, device: Int32 = -1
        var name = [CChar](repeating: 0, count: 128)
        XCTAssertEqual(openpty(&controller, &device, &name, nil, nil), 0)
        defer { close(controller); close(device) }
        let path = String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        XCTAssertTrue(USBLampPort.write("show 0 0 100 blink 1000\n", to: path))
        var buffer = [UInt8](repeating: 0, count: 64)
        let count = read(controller, &buffer, buffer.count)
        XCTAssertEqual(String(decoding: buffer.prefix(max(0, count)), as: UTF8.self), "show 0 0 100 blink 1000\n")
    }

    func testMissingDeviceIsNotAnError() {
        XCTAssertFalse(USBLampPort.write("off\n", to: "/dev/hiboss-lamp-missing"))
    }
}
