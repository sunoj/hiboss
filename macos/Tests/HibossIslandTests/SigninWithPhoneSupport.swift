// Test doubles for "Sign in with iPhone": a scripted SigninRequesting, a step-wise sleeper,
// a settable clock, and an in-memory token store.
// Exports: ScriptedSigninClient, StepSleeper, TestClock, MemoryTokens, eventually(_:).

import Foundation
import HibossKit
import XCTest

actor ScriptedSigninClient: SigninRequesting {
    static let requestID = String(repeating: "c3", count: 16)
    static let server = URL(string: "https://hiboss.example")!

    private var openResult: Result<SigninTicket, SigninError>
    private var statuses: [Result<SigninProgress, SigninError>]
    private var completions: [Result<PairingRedemptionGrant, SigninError>]
    private(set) var openLabels: [String] = []
    private(set) var statusCalls = 0
    private(set) var submittedCodes: [String] = []

    init(
        expiresAt: Date,
        openError: SigninError? = nil,
        statuses: [Result<SigninProgress, SigninError>] = [],
        completions: [Result<PairingRedemptionGrant, SigninError>] = []
    ) {
        let link = SigninLink(serverURL: Self.server, requestID: Self.requestID)!
        let ticket = SigninTicket(link: link, pollToken: "st_test", expiresAt: expiresAt)
        openResult = openError.map { .failure($0) } ?? .success(ticket)
        self.statuses = statuses
        self.completions = completions
    }

    func open(server: URL, deviceLabel: String) async throws -> SigninTicket {
        openLabels.append(deviceLabel)
        return try openResult.get()
    }

    /// Answers from the script in order; `pending` once it runs out.
    func status(_ ticket: SigninTicket) async throws -> SigninProgress {
        statusCalls += 1
        guard !statuses.isEmpty else { return .pending }
        return try statuses.removeFirst().get()
    }

    func complete(
        _ ticket: SigninTicket, code: String, signing: PairingSigningRegistration?
    ) async throws -> PairingRedemptionGrant {
        submittedCodes.append(code)
        guard !completions.isEmpty else { throw SigninError.invalidResponse }
        return try completions.removeFirst().get()
    }

    func script(statuses: [Result<SigninProgress, SigninError>]) {
        self.statuses = statuses
    }
}

/// Each `sleep` suspends until the test calls `tick()`, so the poll loop advances on demand.
actor StepSleeper {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    var pending: Int { waiters.count }

    func sleep() async {
        await withCheckedContinuation { waiters.append($0) }
    }

    func tick() {
        guard !waiters.isEmpty else { return }
        waiters.removeFirst().resume()
    }
}

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ date: Date) { current = date }

    var now: Date {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}

final class MemoryTokens: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    func read() throws -> String? { lock.withLock { token } }
    func write(_ token: String) throws { lock.withLock { self.token = token } }
}

/// Waits up to about two seconds for `condition`; fails the test if it never holds.
@MainActor
func eventually(
    _ message: String = "condition never held",
    file: StaticString = #filePath, line: UInt = #line,
    _ condition: @MainActor () async -> Bool
) async {
    for _ in 0..<400 {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
    XCTFail(message, file: file, line: line)
}
