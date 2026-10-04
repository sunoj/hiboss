// Covers the Mac's "Sign in with iPhone" state machine: approval, code entry, persistence,
// wrong codes, rejection, expiry, cancellation, and the server-address and copy helpers.
// Dependencies: XCTest, HibossKit Signin types, SigninWithPhoneSupport doubles, HibossIsland.

import Foundation
import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class SigninWithPhoneTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var clock: TestClock!
    private var sleeper: StepSleeper!

    override func setUp() async throws {
        clock = TestClock(start)
        sleeper = StepSleeper()
    }

    func testApprovedCodePersistsTheTokenLikePairing() async throws {
        let (settings, tokens, defaults) = try makeSettings()
        settings.deviceLabel = "Studio <Mac>"
        let client = makeClient(statuses: [.success(.pending), .success(.approved)],
                                completions: [.success(Self.grant)])
        let model = makeModel(client, persist: { try settings.adopt($0, server: $1) },
                              label: settings.outgoingDeviceLabel)

        await model.start()
        XCTAssertEqual(model.phase, .awaitingApproval)
        XCTAssertNotNil(model.qrImage)
        XCTAssertEqual(model.serverHost, "hiboss.example")
        await poll(until: .enteringCode, model)
        model.code = "12a34 56789"
        XCTAssertEqual(model.code, "123456", "Only six ASCII digits are kept")
        await model.submitCode()

        let config = ConnectionConfig(serverURL: ScriptedSigninClient.server, bossToken: "hb_boss_signed_in")
        XCTAssertEqual(model.phase, .signedIn(config))
        XCTAssertEqual(try tokens.read(), "hb_boss_signed_in")
        XCTAssertEqual(defaults.string(forKey: AppConstants.Storage.serverURL), "https://hiboss.example")
        XCTAssertEqual(settings.activeClientConfig, config)
        XCTAssertEqual(settings.serverAddress, "https://hiboss.example")
        XCTAssertFalse(model.isPolling)
        XCTAssertNil(model.serverHost, "The ticket is dropped once signed in")
        let labels = await client.openLabels
        let codes = await client.submittedCodes
        XCTAssertEqual(labels, ["Studio Mac"])
        XCTAssertEqual(codes, ["123456"])
    }

    func testWrongCodeKeepsAValidRequestAndAsksAgain() async throws {
        let client = makeClient(statuses: [.success(.approved), .success(.approved)],
                                completions: [.failure(.incorrectCodeOrInvalid)])
        let model = makeModel(client)
        await model.start()
        await poll(until: .enteringCode, model)
        model.code = "000000"
        await model.submitCode()

        XCTAssertEqual(model.phase, .enteringCode)
        XCTAssertEqual(model.notice, .codeMismatch)
        XCTAssertEqual(model.code, "")
        XCTAssertTrue(model.isPolling)
        XCTAssertNotNil(model.expiresAt)
    }

    func testWrongCodeOnARequestThatWasRejectedEndsIt() async throws {
        let client = makeClient(statuses: [.success(.approved), .success(.rejected)],
                                completions: [.failure(.incorrectCodeOrInvalid)])
        let model = makeModel(client)
        await model.start()
        await poll(until: .enteringCode, model)
        model.code = "999999"
        await model.submitCode()

        XCTAssertEqual(model.phase, .ended(.rejected))
        XCTAssertFalse(model.isPolling)
        XCTAssertNil(model.serverHost)
    }

    func testTooManyRequestsWhileCompletingKeepsCodeEntry() async throws {
        let client = makeClient(statuses: [.success(.approved)], completions: [.failure(.tooManyRequests)])
        let model = makeModel(client)
        await model.start()
        await poll(until: .enteringCode, model)
        model.code = "123456"
        await model.submitCode()
        XCTAssertEqual(model.phase, .enteringCode)
        XCTAssertEqual(model.notice, .tooManyRequests)
        XCTAssertEqual(model.code, "123456")
    }

    func testRejectionWhileWaitingEndsTheRequest() async throws {
        let model = makeModel(makeClient(statuses: [.success(.pending), .success(.rejected)]))
        await model.start()
        await poll(until: .ended(.rejected), model)
        XCTAssertFalse(model.isPolling)
        XCTAssertNil(model.qrImage)
    }

    func testCompletionByAnotherDeviceEndsTheRequest() async throws {
        let model = makeModel(makeClient(statuses: [.success(.completed)]))
        await model.start()
        await poll(until: .ended(.usedElsewhere), model)
    }

    func testServerExpiryAndUnknownTokenBothEndAsExpired() async throws {
        for answer in [Result<SigninProgress, SigninError>.success(.expired), .failure(.notFound)] {
            let model = makeModel(makeClient(statuses: [answer]))
            await model.start()
            await poll(until: .ended(.expired), model)
        }
    }

    func testLocalExpiryEndsWithoutAskingTheServer() async throws {
        let client = makeClient(statuses: [])
        let model = makeModel(client)
        await model.start()
        clock.now = start.addingTimeInterval(601)
        await poll(until: .ended(.expired), model)
        let calls = await client.statusCalls
        XCTAssertEqual(calls, 0)
    }

    func testTransientStatusFailureKeepsPolling() async throws {
        let model = makeModel(makeClient(statuses: [.failure(.requestFailed(status: 503)), .success(.approved)]))
        await model.start()
        await poll(until: .enteringCode, model)
    }

    func testCancelStopsPollingAndForgetsTheRequest() async throws {
        let client = makeClient(statuses: [.success(.approved)])
        let model = makeModel(client)
        await model.start()
        await eventually { await self.sleeper.pending == 1 }

        model.cancel()
        await sleeper.tick()
        for _ in 0..<20 { await Task.yield() }

        let calls = await client.statusCalls
        XCTAssertEqual(calls, 0, "No status request after cancel")
        XCTAssertFalse(model.isPolling)
        XCTAssertEqual(model.phase, .editingServer)
        XCTAssertNil(model.qrImage)
        XCTAssertNil(model.expiresAt)
    }

    func testStartOverOpensAFreshRequestAfterAnEnding() async throws {
        let client = makeClient(statuses: [.success(.rejected)])
        let model = makeModel(client)
        await model.start()
        await poll(until: .ended(.rejected), model)
        await model.startOver()
        XCTAssertEqual(model.phase, .awaitingApproval)
        let labels = await client.openLabels
        XCTAssertEqual(labels.count, 2)
    }

    func testFailedPersistenceAfterAGrantEndsAsFailed() async throws {
        let client = makeClient(statuses: [.success(.approved)], completions: [.success(Self.grant)])
        let model = makeModel(client, persist: { _, _ in throw SettingsError.keychain(-1) })
        await model.start()
        await poll(until: .enteringCode, model)
        model.code = "123456"
        await model.submitCode()
        XCTAssertEqual(model.phase, .ended(.failed))
    }

    func testOpenFailuresStayOnTheServerStep() async throws {
        let busy = makeModel(makeClient(openError: .tooManyRequests))
        await busy.start()
        XCTAssertEqual(busy.phase, .editingServer)
        XCTAssertEqual(busy.notice, .tooManyRequests)

        let client = makeClient()
        let insecure = makeModel(client, server: "http://hiboss.example")
        await insecure.start()
        XCTAssertEqual(insecure.phase, .editingServer)
        XCTAssertEqual(insecure.notice, .invalidServer(.insecureServer))
        let labels = await client.openLabels
        XCTAssertTrue(labels.isEmpty, "An insecure server is never contacted")
    }

    func testServerAddressDefaultsToHTTPSAndAllowsPlainHTTPOnlyLocally() {
        XCTAssertEqual(try SigninServerAddress.url(from: " hiboss.example ").get().absoluteString, "https://hiboss.example")
        XCTAssertEqual(try SigninServerAddress.url(from: "http://localhost:8787").get().absoluteString, "http://localhost:8787")
        XCTAssertEqual(SigninServerAddress.url(from: "http://hiboss.example"), .failure(.insecureServer))
        XCTAssertEqual(SigninServerAddress.url(from: ""), .failure(.invalidServerURL))
        XCTAssertEqual(SigninServerAddress.url(from: "ftp://hiboss.example"), .failure(.invalidServerURL))
    }

    func testCopyIsDistinctAndLocalized() throws {
        let endings: [SigninWithPhoneModel.Ending] = [.rejected, .expired, .usedElsewhere, .failed]
        XCTAssertEqual(Set(endings.map { SigninPhoneCopy.ending($0).title }).count, endings.count)
        let notices: [SigninWithPhoneModel.Notice] = [.codeMismatch, .tooManyRequests, .requestFailed]
        XCTAssertEqual(Set(notices.map(SigninPhoneCopy.notice)).count, notices.count)
        XCTAssertEqual(ConnectionSheet.signinWithPhone.id, "signinWithPhone")
        let path = try XCTUnwrap(appResourceBundle.path(forResource: "zh-Hans", ofType: "lproj"))
        let bundle = try XCTUnwrap(Bundle(path: path))
        XCTAssertEqual(String(localized: "Sign in with iPhone", bundle: bundle, locale: Locale(identifier: "zh-Hans")),
                       "用 iPhone 登录")
    }

    // MARK: - Helpers

    private static let grant = PairingRedemptionGrant(token: "hb_boss_signed_in", bossID: "boss-1", signingKeyID: nil)

    private func makeClient(
        openError: SigninError? = nil,
        statuses: [Result<SigninProgress, SigninError>] = [],
        completions: [Result<PairingRedemptionGrant, SigninError>] = []
    ) -> ScriptedSigninClient {
        ScriptedSigninClient(expiresAt: start.addingTimeInterval(600), openError: openError,
                             statuses: statuses, completions: completions)
    }

    private func makeModel(
        _ client: ScriptedSigninClient,
        persist: @escaping SigninWithPhoneModel.Persist = { grant, server in
            ConnectionConfig(serverURL: server, bossToken: grant.token)
        },
        label: String = "Mac",
        server: String = "hiboss.example"
    ) -> SigninWithPhoneModel {
        let sleeper = sleeper!
        let clock = clock!
        return SigninWithPhoneModel(
            serverAddress: server, deviceLabel: label, client: client,
            sleep: { _ in await sleeper.sleep() }, now: { clock.now }, persist: persist
        )
    }

    /// Releases one poll at a time until the model reaches `phase`.
    private func poll(until phase: SigninWithPhoneModel.Phase, _ model: SigninWithPhoneModel,
                      file: StaticString = #filePath, line: UInt = #line) async {
        await eventually("never reached \(phase)", file: file, line: line) {
            if model.phase == phase { return true }
            await self.sleeper.tick()
            return model.phase == phase
        }
    }

    private func makeSettings() throws -> (AppSettings, MemoryTokens, UserDefaults) {
        let suite = "SigninWithPhoneTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let tokens = MemoryTokens()
        return (AppSettings(defaults: defaults, keychain: tokens), tokens, defaults)
    }
}
