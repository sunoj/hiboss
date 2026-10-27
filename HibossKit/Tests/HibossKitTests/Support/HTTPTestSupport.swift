// Network fixtures shared by isolated HibossKit API test protocols.
// Exports: HTTPTestSupport for ephemeral sessions, JSON responses and request-body reads.
// Dependencies: Foundation, XCTest and HibossKit's invalid-response error.

import Foundation
import XCTest
import HibossKit

enum HTTPTestSupport {
    static func session(for protocolClass: URLProtocol.Type) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [protocolClass]
        return URLSession(configuration: configuration)
    }

    static func response(
        for request: URLRequest,
        json: String
    ) throws -> (HTTPURLResponse, Data) {
        let url = try XCTUnwrap(request.url)
        let response = try XCTUnwrap(
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        )
        return (response, Data(json.utf8))
    }

    static func bodyData(from request: URLRequest, bufferSize: Int = 1024) throws -> Data {
        if let body = request.httpBody {
            return body
        }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 {
                throw stream.streamError ?? HibossAPIError.invalidResponse
            }
            if count == 0 {
                return data
            }
            data.append(buffer, count: count)
        }
    }
}
