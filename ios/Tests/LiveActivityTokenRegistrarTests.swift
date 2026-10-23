// Live Activity push tokens reach the server only in direct mode, with retries on failure.
// Exports: LiveActivityTokenRegistrarTests.
// Dependencies: XCTest, HibossKit PushMode, LiveActivityTokenRegistrar.

import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class LiveActivityTokenRegistrarTests: XCTestCase {
    private func registrar(mode: PushMode?, api: RecordingTokenAPI) -> LiveActivityTokenRegistrar {
        let registrar = LiveActivityTokenRegistrar()
        registrar.mode = { mode }
        registrar.api = { api }
        registrar.environment = { "sandbox" }
        registrar.retryDelays = [.milliseconds(1), .milliseconds(1)]
        return registrar
    }

    func testDirectModeRegistersTheHexToken() async {
        let api = RecordingTokenAPI()
        let accepted = await registrar(mode: .direct, api: api).register(token: Data([0xab, 0x01]), messageID: "m1")
        XCTAssertTrue(accepted)
        let calls = await api.calls
        XCTAssertEqual(calls, ["m1|ab01|sandbox"])
    }

    func testRelayAndUnknownModesNeverRegister() async {
        for mode in [PushMode.relay, .unavailable, nil] {
            let api = RecordingTokenAPI()
            let registrar = registrar(mode: mode, api: api)
            XCTAssertNil(registrar.pushType)
            let accepted = await registrar.register(token: Data([1]), messageID: "m1")
            XCTAssertFalse(accepted)
            let calls = await api.calls
            XCTAssertEqual(calls, [])
        }
        XCTAssertEqual(registrar(mode: .direct, api: RecordingTokenAPI()).pushType, .token)
    }

    func testFailureRetriesUntilAccepted() async {
        let api = RecordingTokenAPI(failures: 2)
        let accepted = await registrar(mode: .direct, api: api).register(token: Data([2]), messageID: "m1")
        XCTAssertTrue(accepted)
        let count = await api.calls.count
        XCTAssertEqual(count, 3)
    }

    func testConflictStopsRegistering() async {
        let api = RecordingTokenAPI(failures: 1, status: 409)
        let registrar = registrar(mode: .direct, api: api)
        let first = await registrar.register(token: Data([3]), messageID: "m1")
        let second = await registrar.register(token: Data([4]), messageID: "m2")
        XCTAssertFalse(first)
        XCTAssertFalse(second)
        XCTAssertTrue(registrar.refused)
        let count = await api.calls.count
        XCTAssertEqual(count, 1)
    }
}

actor RecordingTokenAPI: LiveActivityTokenServing {
    private(set) var calls: [String] = []
    private var failures: Int
    private let status: Int?

    /// `status` nil fails like a dropped connection; otherwise like an HTTP error answer.
    init(failures: Int = 0, status: Int? = nil) {
        self.failures = failures
        self.status = status
    }

    func registerLiveActivityToken(messageID: String, token: String, environment: String) async throws {
        calls.append("\(messageID)|\(token)|\(environment)")
        if failures > 0 {
            failures -= 1
            if let status { throw HibossAPIError.requestFailed(status: status, message: "") }
            throw URLError(.timedOut)
        }
    }
}
