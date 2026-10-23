// Resolution pushes: direct and relay payloads retract the ask; anything unreadable is a no-op.
// Exports: ResolutionPushTests and the RecordingResolutionEffects / FakeNotificationCenter fakes.
// Dependencies: XCTest, PushPayloadCipher, ResolutionPush, SystemResolutionEffects.

import XCTest
@testable import HiBoss

@MainActor
final class ResolutionPushTests: XCTestCase {
    private let key = Data((0..<32).map { UInt8($0) })

    private func relayPayload(_ plaintext: String, kind: PushKind = .resolved, key: Data? = nil) throws
        -> [AnyHashable: Any]
    {
        let sealed = try PushPayloadCipher.seal(Data(plaintext.utf8), pushKey: key ?? self.key, kind: kind)
        return ["aps": ["content-available": 1], "e": sealed]
    }

    func testDirectPayloadRetractsTheAsk() async {
        let info: [AnyHashable: Any] = ["aps": ["content-available": 1],
                                        "hiboss": ["resolved": ["id": "m_42", "status": "replied"]]]
        let effects = RecordingResolutionEffects()
        let handled = await ResolutionPush.handle(ResolutionPush.decode(info, pushKey: nil), effects: effects)
        XCTAssertTrue(handled)
        XCTAssertEqual(effects.calls, ["notifications:m_42", "activity:m_42", "inbox:m_42"])
    }

    func testRelayPayloadRetractsTheAsk() async throws {
        let info = try relayPayload(#"{"id":"m_7","status":"expired"}"#)
        let effects = RecordingResolutionEffects()
        let handled = await ResolutionPush.handle(ResolutionPush.decode(info, pushKey: key), effects: effects)
        XCTAssertTrue(handled)
        XCTAssertEqual(effects.calls, ["notifications:m_7", "activity:m_7", "inbox:m_7"])
    }

    func testDecryptFailureIsANoOp() async throws {
        let plaintext = #"{"id":"m_7","status":"expired"}"#
        let unreadable: [[AnyHashable: Any]] = [
            try relayPayload(plaintext, key: Data(repeating: 9, count: 32)),
            try relayPayload(plaintext, kind: .decision),
            ["aps": ["content-available": 1], "e": "not-base64!"],
        ]
        for info in unreadable {
            let effects = RecordingResolutionEffects()
            let handled = await ResolutionPush.handle(ResolutionPush.decode(info, pushKey: key), effects: effects)
            XCTAssertFalse(handled)
            XCTAssertEqual(effects.calls, [])
        }
        XCTAssertNil(ResolutionPush.decode(try relayPayload(plaintext), pushKey: nil))
    }

    func testAlertsAndUnknownStatusesAreNotResolutions() throws {
        var alert = try relayPayload(#"{"id":"m_7","status":"replied"}"#)
        alert["aps"] = ["alert": ["loc-key": "HIBOSS_PUSH_DECISION"]]
        XCTAssertNil(ResolutionPush.decode(alert, pushKey: key))
        XCTAssertNil(ResolutionPush.decode(["hiboss": ["resolved": ["id": "m", "status": "open"]]], pushKey: nil))
        XCTAssertNil(ResolutionPush.decode(["messageId": "m"], pushKey: nil))
    }

    func testSystemEffectsRemoveOnlyTheAsksNotifications() async {
        let center = FakeNotificationCenter(records: [
            .init(identifier: "a", date: .distantPast, messageID: "m_42", category: "HIBOSS_OPTIONS"),
            .init(identifier: "b", date: .distantPast, messageID: "m_43", category: "HIBOSS_OPTIONS"),
            .init(identifier: "c", date: .distantPast, messageID: "m_42", category: "HIBOSS_MESSAGE"),
        ])
        await SystemResolutionEffects(center: center).removeDeliveredNotifications(forAsk: "m_42")
        XCTAssertEqual(center.removed, ["a", "c"])
    }

    func testRecordReadsDirectAndRelayUserInfo() {
        let direct = DeliveredAskNotifications.record(
            identifier: "x", date: .distantPast,
            userInfo: ["aps": ["category": "HIBOSS_OPTIONS"], "messageId": "m_1"])
        XCTAssertEqual(direct.messageID, "m_1")
        XCTAssertEqual(direct.category, "HIBOSS_OPTIONS")
        let relay = DeliveredAskNotifications.record(
            identifier: "y", date: .distantPast, userInfo: ["category": "HIBOSS_MESSAGE", "messageId": "m_2"])
        XCTAssertEqual(relay.category, "HIBOSS_MESSAGE")
    }
}

@MainActor
final class RecordingResolutionEffects: ResolutionEffects {
    private(set) var calls: [String] = []
    func removeDeliveredNotifications(forAsk id: String) async { calls.append("notifications:\(id)") }
    func endActivity(forAsk id: String) async { calls.append("activity:\(id)") }
    func markClosed(_ id: String) { calls.append("inbox:\(id)") }
}

@MainActor
final class FakeNotificationCenter: DeliveredNotificationCenter {
    var records: [DeliveredNotificationRecord]
    private(set) var removed: [String] = []
    init(records: [DeliveredNotificationRecord]) { self.records = records }
    func delivered() async -> [DeliveredNotificationRecord] { records }
    func remove(identifiers: [String]) { removed += identifiers }
}
