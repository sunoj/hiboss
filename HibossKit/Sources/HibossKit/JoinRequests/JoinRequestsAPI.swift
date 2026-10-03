// Authenticated join-request routes: list pending, approve, and reject.
// Exports: JoinRequestServing and HibossAPI's conformance with typed 403/404/409 errors.
// Dependencies: Foundation networking and HibossAPI's authorized request helper.

import Foundation

public protocol JoinRequestServing: Sendable {
    func listPendingJoinRequests() async throws -> [JoinRequest]
    func approveJoinRequest(id: String) async throws -> JoinApproval
    func rejectJoinRequest(id: String) async throws
}

extension HibossAPI: JoinRequestServing {
    public func listPendingJoinRequests() async throws -> [JoinRequest] {
        let url = joinRequestsURL.appending(queryItems: [URLQueryItem(name: "status", value: "pending")])
        let data = try await joinRequestCall(url: url, method: "GET")
        do {
            return try decoder.decode(JoinRequestList.self, from: data).requests
        } catch {
            throw HibossAPIError.decodingFailed(
                context: "join requests", body: String(data: data, encoding: .utf8) ?? "<non-text>"
            )
        }
    }

    public func approveJoinRequest(id: String) async throws -> JoinApproval {
        let url = joinRequestsURL.appendingPathComponent(id).appendingPathComponent("approve")
        let data = try await joinRequestCall(url: url, method: "POST")
        do {
            return try decoder.decode(JoinApproval.self, from: data)
        } catch {
            throw HibossAPIError.decodingFailed(
                context: "join approval", body: String(data: data, encoding: .utf8) ?? "<non-text>"
            )
        }
    }

    public func rejectJoinRequest(id: String) async throws {
        let url = joinRequestsURL.appendingPathComponent(id).appendingPathComponent("reject")
        _ = try await joinRequestCall(url: url, method: "POST")
    }

    private var joinRequestsURL: URL {
        apiURL.appendingPathComponent("join-requests")
    }

    /// 403, 404 and 409 carry plain-text bodies; only the 409 text is shown to the boss.
    private func joinRequestCall(url: URL, method: String) async throws -> Data {
        let request = authorizedRequest(url: url, method: method)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HibossAPIError.invalidResponse }
        switch http.statusCode {
        case 200..<300: return data
        case 403: throw JoinRequestError.forbidden
        case 404: throw JoinRequestError.notFound
        case 409: throw JoinRequestError.conflict(Self.plainText(data))
        default: throw HibossAPIError.requestFailed(status: http.statusCode, message: "")
        }
    }

    private static func plainText(_ data: Data) -> String {
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return String(text.prefix(200))
    }
}

private struct JoinRequestList: Decodable {
    let requests: [JoinRequest]
}
