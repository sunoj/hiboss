// URLProtocol stub standing in for both the HiBoss server and the push relay in tests.
// Exports: PushRelayStub (recorded requests, scripted statuses) and MemoryRelayCredentialStore.
// Dependencies: Foundation, XCTest, RelayCredentialStoring.

import Foundation
import XCTest
@testable import HiBoss

struct RecordedRequest: Sendable {
    let method: String
    let url: URL
    let authorization: String?
    let body: [String: String]

    var route: String { "\(method) \(url.host ?? "")\(url.path)" }
}

final class PushRelayStub: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var recorded: [RecordedRequest] = []
    /// Route → status; unlisted routes answer the success status for their method.
    nonisolated(unsafe) private static var statuses: [String: Int] = [:]
    nonisolated(unsafe) private static var pushMode = "relay"
    nonisolated(unsafe) private static var minted = 0

    static func reset(pushMode mode: String = "relay", statuses routes: [String: Int] = [:]) {
        lock.withLock { recorded = []; statuses = routes; pushMode = mode; minted = 0 }
    }

    static func set(_ route: String, status: Int) { lock.withLock { statuses[route] = status } }
    /// Continues minting after `count` earlier registrations, so a re-registration gets a new handle.
    static func mintedOffset(_ count: Int) { lock.withLock { minted = count } }
    static var requests: [RecordedRequest] { lock.withLock { recorded } }
    static var routes: [String] { requests.map(\.route) }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PushRelayStub.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url, let method = request.httpMethod else { return XCTFail("bad request") }
        let entry = RecordedRequest(method: method, url: url,
                                    authorization: request.value(forHTTPHeaderField: "Authorization"),
                                    body: Self.body(of: request))
        let (status, body) = Self.lock.withLock { () -> (Int, String) in
            Self.recorded.append(entry)
            let status = Self.statuses[entry.route] ?? (method == "POST" && url.path == "/v1/registrations"
                ? 201 : url.host == "relay.example" ? 204 : 200)
            if url.path == "/v1/registrations", status == 201 {
                Self.minted += 1
                let handle = String(repeating: "h", count: 42) + "\(Self.minted % 10)"
                return (status, #"{"handle":"\#(handle)","deviceSecret":"secret-\#(Self.minted)"}"#)
            }
            if url.host == "relay.example", status == 400 { return (status, #"{"error":"invalid_token"}"#) }
            guard url.path.hasSuffix("/me") else { return (status, "{}") }
            let mode = Self.pushMode.isEmpty ? "" : #","pushMode":"\#(Self.pushMode)""#
            return (status, #"{"id":"b1"\#(mode)}"#)
        }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
        else { return XCTFail("bad response") }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func body(of request: URLRequest) -> [String: String] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: String]) ?? [:]
    }
}

final class MemoryRelayCredentialStore: RelayCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: RelayCredentials?

    func read() throws -> RelayCredentials? { lock.withLock { stored } }
    func write(_ credentials: RelayCredentials) throws { lock.withLock { stored = credentials } }
    func delete() throws { lock.withLock { stored = nil } }
}
