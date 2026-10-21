// Relay registration against stubbed server and relay: register, rotate, re-register, sign-out.
// Exports: PushRelayRegistrationTests.
// Dependencies: XCTest, HibossKit, PushRelayStub, PushRelayRegistrar, PushRoute.

import HibossKit
import UserNotifications
import XCTest
@testable import HiBoss

@MainActor
final class PushRelayRegistrationTests: XCTestCase {
    private var store: MemoryRelayCredentialStore!
    private var registrar: PushRelayRegistrar!
    private var api: HibossAPI!
    private let tokenA = String(repeating: "ab", count: 32)
    private let tokenB = String(repeating: "cd", count: 32)

    override func setUp() async throws {
        PushRelayStub.reset()
        store = MemoryRelayCredentialStore()
        let session = PushRelayStub.session()
        registrar = PushRelayRegistrar(
            client: PushRelayClient(baseURL: try XCTUnwrap(URL(string: "https://relay.example")), session: session),
            store: store)
        api = HibossAPI(config: ConnectionConfig(serverURL: try XCTUnwrap(URL(string: "https://server.example")),
                                                 bossToken: "boss-token"), session: session)
    }

    private func route(_ token: String) async -> PushRouteOutcome {
        await PushRoute.register(token: token, bundleId: "ai.hiboss.app", environment: "sandbox",
                                 api: api, relay: registrar)
    }

    func testRelayModeRegistersOnceAndGivesTheServerHandleAndKey() async throws {
        let outcome = await route(tokenA)
        XCTAssertEqual(outcome, PushRouteOutcome(mode: .relay, registration: .registered))
        XCTAssertEqual(PushRelayStub.routes, ["GET server.example/api/boss/me",
                                              "POST relay.example/v1/registrations",
                                              "POST server.example/api/boss/devices"])
        let relay = PushRelayStub.requests[1]
        XCTAssertEqual(relay.body, ["apnsToken": tokenA, "environment": "sandbox"])
        XCTAssertNil(relay.authorization, "the relay never sees the boss token")
        let server = PushRelayStub.requests[2].body
        let stored = try XCTUnwrap(store.read())
        XCTAssertEqual(server, ["relayHandle": stored.handle, "pushKey": stored.pushKey,
                                "environment": "sandbox", "platform": "ios", "bundleId": "ai.hiboss.app"])
        XCTAssertEqual(Base64URL.decode(stored.pushKey)?.count, 32)
        XCTAssertEqual(stored.pushKey.count, 43, "unpadded base64url, as the server validates")
        XCTAssertFalse(relay.body.values.contains(stored.pushKey), "the push key never reaches the relay")
        XCTAssertEqual(stored.deviceSecret, "secret-1")
    }

    func testSameTokenSkipsTheRelayAndRotatedTokenIsPut() async throws {
        _ = await route(tokenA)
        let first = try XCTUnwrap(store.read())
        PushRelayStub.reset()
        _ = await route(tokenA)
        XCTAssertEqual(PushRelayStub.routes, ["GET server.example/api/boss/me", "POST server.example/api/boss/devices"])

        PushRelayStub.reset()
        let outcome = await route(tokenB)
        XCTAssertEqual(outcome.registration, .registered)
        XCTAssertEqual(PushRelayStub.routes, ["GET server.example/api/boss/me",
                                              "PUT relay.example/v1/registrations/self",
                                              "POST server.example/api/boss/devices"])
        XCTAssertEqual(PushRelayStub.requests[1].authorization, "Bearer secret-1")
        XCTAssertEqual(PushRelayStub.requests[1].body, ["apnsToken": tokenB, "environment": "sandbox"])
        let rotated = try XCTUnwrap(store.read())
        XCTAssertEqual(rotated.handle, first.handle)
        XCTAssertEqual(rotated.pushKey, first.pushKey)
        XCTAssertEqual(rotated.apnsToken, tokenB)
    }

    func testGoneSecretRegistersAgainAndDropsTheOldServerRow() async throws {
        _ = await route(tokenA)
        let old = try XCTUnwrap(store.read())
        PushRelayStub.reset(statuses: ["PUT relay.example/v1/registrations/self": 410])
        _ = await route(tokenB)
        XCTAssertEqual(PushRelayStub.routes, ["GET server.example/api/boss/me",
                                              "PUT relay.example/v1/registrations/self",
                                              "DELETE server.example/api/boss/devices/\(old.serverDeviceID)",
                                              "POST relay.example/v1/registrations",
                                              "POST server.example/api/boss/devices"])
        let fresh = try XCTUnwrap(store.read())
        XCTAssertNotEqual(fresh.pushKey, old.pushKey)
        XCTAssertEqual(fresh.apnsToken, tokenB)
    }

    func testSignOutDeletesAtRelayAndServerThenErases() async throws {
        _ = await route(tokenA)
        let stored = try XCTUnwrap(store.read())
        PushRelayStub.reset()
        await registrar.unregister(api: api)
        XCTAssertEqual(PushRelayStub.routes, ["DELETE relay.example/v1/registrations/self",
                                              "DELETE server.example/api/boss/devices/relay:\(stored.handle)"])
        XCTAssertEqual(PushRelayStub.requests[0].authorization, "Bearer secret-1")
        XCTAssertEqual(PushRelayStub.requests[1].authorization, "Bearer boss-token")
        XCTAssertNil(try store.read())
    }

    func testSignOutErasesEvenWhenTheRelayFails() async throws {
        _ = await route(tokenA)
        PushRelayStub.reset(statuses: ["DELETE relay.example/v1/registrations/self": 503])
        await registrar.unregister(api: api)
        XCTAssertNil(try store.read())
    }

    func testRelayFailureIsReportedWithoutStoringCredentials() async throws {
        PushRelayStub.reset(statuses: ["POST relay.example/v1/registrations": 429])
        let outcome = await route(tokenA)
        XCTAssertEqual(outcome.mode, .relay)
        guard case .failed = outcome.registration else { return XCTFail("expected failure") }
        XCTAssertNil(try store.read())
        XCTAssertFalse(PushRelayStub.routes.contains("POST server.example/api/boss/devices"))
    }

    func testDirectModeKeepsTheTokenPathAndNeverCallsTheRelay() async throws {
        PushRelayStub.reset(pushMode: "direct")
        let outcome = await route(tokenA)
        XCTAssertEqual(outcome, PushRouteOutcome(mode: .direct, registration: .registered))
        XCTAssertEqual(PushRelayStub.routes, ["GET server.example/api/boss/me", "POST server.example/api/boss/devices"])
        XCTAssertEqual(PushRelayStub.requests[1].body["token"], tokenA)
    }

    func testNoneModeRegistersNothingAndNeverPrompts() async throws {
        PushRelayStub.reset(pushMode: "none")
        let outcome = await route(tokenA)
        XCTAssertEqual(outcome, PushRouteOutcome(mode: .unavailable, registration: .idle))
        XCTAssertEqual(PushRelayStub.routes, ["GET server.example/api/boss/me"])
        XCTAssertFalse(PushManager.shouldPrompt(mode: .unavailable, status: .notDetermined))
        XCTAssertTrue(PushManager.shouldPrompt(mode: .relay, status: .notDetermined))
        XCTAssertTrue(PushManager.shouldPrompt(mode: nil, status: .notDetermined))
        XCTAssertFalse(PushManager.shouldPrompt(mode: .direct, status: .denied))
    }

    func testServerWithoutPushModeIsDirect() async throws {
        PushRelayStub.reset(pushMode: "")
        let mode = try await api.fetchPushMode()
        XCTAssertEqual(mode, .direct)
    }
}
