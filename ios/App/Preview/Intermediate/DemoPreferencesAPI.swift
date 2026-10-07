// Holds the existing Settings preference UI through a synthetic URLSession transport.
// Exports DemoPreferencesAPI; never contacts a server or changes Settings-owned views.
// Dependencies: Foundation, HibossKit and DemoDelay.

import Foundation
import HibossKit

enum DemoPreferencesAPI {
    static func make() -> HibossAPI? {
        guard let server = URL(string: "https://preferences.demo.invalid") else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HeldPreferencesProtocol.self]
        return HibossAPI(config: ConnectionConfig(serverURL: server, bossToken: "demo"),
                         session: URLSession(configuration: configuration))
    }
}

private final class HeldPreferencesProtocol: URLProtocol, @unchecked Sendable {
    private var loading: Task<Void, Never>?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        loading = Task {
            do {
                guard let url = request.url,
                      let response = HTTPURLResponse(url: url, statusCode: 200,
                                                     httpVersion: nil, headerFields: nil) else { return }
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                try await holdResponse(request.httpMethod == "PUT" ? "PREFERENCES_SAVE" : "PREFERENCES")
                guard !Task.isCancelled else { return }
                client?.urlProtocol(self, didLoad: request.httpBody ?? Data("{}".utf8))
                client?.urlProtocolDidFinishLoading(self)
            } catch { return }
        }
    }

    private func holdResponse(_ source: String) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await DemoDelay.wait(source) }
            group.addTask { @Sendable [self] in
                while !Task.isCancelled {
                    client?.urlProtocol(self, didLoad: Data(" ".utf8))
                    try await Task.sleep(for: .seconds(5))
                }
            }
            try await group.next()
            group.cancelAll()
        }
    }

    override func stopLoading() { loading?.cancel() }
}
