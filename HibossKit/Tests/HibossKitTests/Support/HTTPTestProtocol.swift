// HTTP response delivery shared by isolated API test protocols.
// Subclasses retain their own handlers and missing-handler policies.
// Depends on Foundation URLProtocol; no production networking code is changed.

import Foundation

class HTTPTestProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    func complete(_ load: () throws -> (HTTPURLResponse, Data)) {
        do {
            let (response, data) = try load()
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}
