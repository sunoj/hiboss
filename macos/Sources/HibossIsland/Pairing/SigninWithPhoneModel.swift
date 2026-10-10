// Drives "Sign in with iPhone" on a signed-out Mac: open a request, poll it, take the code.
// Exports: SigninWithPhoneModel and SigninServerAddress.
// Dependencies: HibossKit SigninRequesting and PairingQRCode; the ticket stays in memory only.

import CoreGraphics
import Foundation
import HibossKit

@MainActor
final class SigninWithPhoneModel: ObservableObject {
    enum Phase: Equatable {
        case editingServer
        case opening
        case awaitingApproval
        case enteringCode
        case completing
        case signedIn(ConnectionConfig)
        case ended(Ending)
    }

    enum Ending: Equatable {
        case rejected, expired, usedElsewhere, failed
    }

    enum Notice: Equatable {
        case invalidServer(PairingPayloadError)
        case codeMismatch
        case tooManyRequests
        case requestFailed
    }

    typealias Persist = @MainActor (PairingRedemptionGrant, URL) throws -> ConnectionConfig
    typealias Sleep = @Sendable (Duration) async throws -> Void

    static let codeLength = 6
    static let pollInterval = Duration.seconds(1)

    @Published var serverAddress: String
    @Published var code = "" { didSet { normalizeCode() } }
    @Published private(set) var phase: Phase = .editingServer
    @Published private(set) var notice: Notice?
    @Published private(set) var qrImage: CGImage?
    /// Holds the poll token, a credential: never published, logged or persisted.
    private var ticket: SigninTicket?
    private var pollTask: Task<Void, Never>?
    /// Bumped by `cancel()` so an open request that returns late is ignored.
    private var generation = 0

    private let client: any SigninRequesting
    private let deviceLabel: String
    private let persist: Persist
    private let sleep: Sleep
    private let now: () -> Date

    init(
        serverAddress: String,
        deviceLabel: String,
        client: any SigninRequesting = SigninClient(),
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
        now: @escaping () -> Date = Date.init,
        persist: @escaping Persist
    ) {
        self.serverAddress = serverAddress
        self.deviceLabel = deviceLabel
        self.client = client
        self.sleep = sleep
        self.now = now
        self.persist = persist
    }

    var serverHost: String? { ticket?.link.serverHost }
    var expiresAt: Date? { ticket?.expiresAt }
    var isPolling: Bool { pollTask != nil }
    var canStart: Bool { phase == .editingServer && !serverAddress.trimmingCharacters(in: .whitespaces).isEmpty }
    var canSubmitCode: Bool { phase == .enteringCode && code.count == Self.codeLength }

    /// Opens a request on the typed server and starts polling it.
    func start() async {
        guard phase == .editingServer else { return }
        let server: URL
        switch SigninServerAddress.url(from: serverAddress) {
        case let .success(url): server = url
        case let .failure(error):
            notice = .invalidServer(error)
            return
        }
        phase = .opening
        notice = nil
        let attempt = generation
        do {
            let opened = try await client.open(server: server, deviceLabel: deviceLabel)
            guard attempt == generation else { return }
            ticket = opened
            qrImage = opened.link.url.flatMap { PairingQRCode.cgImage(for: $0) }
            phase = .awaitingApproval
            startPolling(opened)
        } catch {
            guard attempt == generation else { return }
            phase = .editingServer
            notice = (error as? SigninError) == .tooManyRequests ? .tooManyRequests : .requestFailed
        }
    }

    /// Opens a fresh request on the same server after a request ended.
    func startOver() async {
        cancel()
        await start()
    }

    /// Stops polling and forgets the request; the sheet calls this when it closes.
    func cancel() {
        generation += 1
        pollTask?.cancel()
        pollTask = nil
        ticket = nil
        qrImage = nil
        code = ""
        notice = nil
        phase = .editingServer
    }

    func submitCode() async {
        guard canSubmitCode, let ticket else { return }
        phase = .completing
        notice = nil
        let grant: PairingRedemptionGrant
        do {
            grant = try await client.complete(ticket, code: code, signing: nil)
        } catch {
            await recover(from: error, ticket: ticket)
            return
        }
        guard ticket == self.ticket else { return }
        do {
            let config = try persist(grant, ticket.link.serverURL)
            stopTracking()
            phase = .signedIn(config)
        } catch {
            end(.failed)
        }
    }

    private func recover(from error: Error, ticket: SigninTicket) async {
        guard ticket == self.ticket else { return }
        switch error as? SigninError {
        case .incorrectCodeOrInvalid?: await recheck(ticket)
        case .tooManyRequests?: resumeCodeEntry(.tooManyRequests)
        default: resumeCodeEntry(.requestFailed)
        }
    }

    /// A 400 does not say which check failed; the status tells a wrong code from a dead request.
    private func recheck(_ ticket: SigninTicket) async {
        let progress: SigninProgress?
        do {
            progress = try await client.status(ticket)
        } catch SigninError.notFound {
            progress = .expired
        } catch {
            progress = nil
        }
        guard ticket == self.ticket else { return }
        if let progress, progress != .pending, progress != .approved {
            _ = apply(progress)
        } else {
            resumeCodeEntry(.codeMismatch)
        }
    }

    private func resumeCodeEntry(_ notice: Notice) {
        phase = .enteringCode
        self.notice = notice
        if notice == .codeMismatch { code = "" }
    }

    private func startPolling(_ ticket: SigninTicket) {
        pollTask?.cancel()
        let sleep = sleep
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await sleep(Self.pollInterval) } catch { return }
                guard !Task.isCancelled, let self, await self.pollOnce(ticket) else { return }
            }
        }
    }

    /// One status check; false once the request has reached an end.
    private func pollOnce(_ ticket: SigninTicket) async -> Bool {
        guard ticket == self.ticket else { return false }
        if phase == .completing { return true }
        if now() >= ticket.expiresAt { return apply(.expired) }
        let progress: SigninProgress
        do {
            progress = try await client.status(ticket)
        } catch SigninError.notFound {
            progress = .expired
        } catch {
            return true // A transient failure: keep polling until the request expires.
        }
        guard ticket == self.ticket, !Task.isCancelled else { return false }
        if phase == .completing { return true }
        return apply(progress)
    }

    /// Applies a server status; false when it ends the request.
    private func apply(_ progress: SigninProgress) -> Bool {
        switch progress {
        case .pending:
            return true
        case .approved:
            if phase == .awaitingApproval { phase = .enteringCode }
            return true
        case .rejected: end(.rejected)
        case .expired: end(.expired)
        case .completed: end(.usedElsewhere)
        }
        return false
    }

    private func end(_ ending: Ending) {
        stopTracking()
        notice = nil
        phase = .ended(ending)
    }

    private func stopTracking() {
        pollTask?.cancel()
        pollTask = nil
        ticket = nil
        qrImage = nil
        code = ""
    }

    private func normalizeCode() {
        let digits = String(code.filter { $0.isASCII && $0.isNumber }.prefix(Self.codeLength))
        if digits != code { code = digits }
    }
}

/// Turns a typed server address into a URL a sign-in link accepts. A bare host means https.
enum SigninServerAddress {
    static func url(from text: String) -> Result<URL, PairingPayloadError> {
        let address = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return .failure(.invalidServerURL) }
        let withScheme = address.contains("://") ? address : "https://" + address
        guard let url = URL(string: withScheme),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host(), !host.isEmpty else {
            return .failure(.invalidServerURL)
        }
        let isLoopback = ["localhost", "127.0.0.1"].contains(host.lowercased())
        guard scheme == "https" || isLoopback else { return .failure(.insecureServer) }
        return .success(url)
    }
}
