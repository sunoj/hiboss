// Demo pairing issuer, join-request and Mac sign-in services so device screens render without a server.
// Exports: DemoPairingIssuer, DemoJoinRequestsAPI, DemoSigninAPI and DemoDevices.serverURL.
// Dependencies: Foundation, HibossKit pairing and join-request contracts. Demo runs only.

import Foundation
import HibossKit

enum DemoDevices {
    static let serverURL = URL(string: "https://hiboss.example.com")!
}

/// Issues a well-formed code that never redeems. `HIBOSS_DEMO_PAIRING_TTL` (seconds)
/// shortens its life so the expired state can be reached in a UI test.
struct DemoPairingIssuer: PairingIssuing {
    func requestPairingCode() async throws -> PairingGrant {
        let raw = ProcessInfo.processInfo.environment["HIBOSS_DEMO_PAIRING_TTL"] ?? ""
        let ttl = TimeInterval(raw) ?? 300
        return try PairingGrant(code: "hb_pair_" + String(repeating: "0123456789abcdef", count: 4),
                                expiresAt: Date().addingTimeInterval(ttl))
    }

    func pairingStatus(code: String) async throws -> PairingStatus { .pending }
}

/// Two pending machines: one approvable, one without a verification code.
final class DemoJoinRequestsAPI: JoinRequestServing, @unchecked Sendable {
    /// One instance per launch, so an approval removes the row on the next refresh.
    static let shared = DemoJoinRequestsAPI()

    private var requests: [JoinRequest] = [
        JoinRequest(
            id: "jr-build", deviceLabel: "build-box-2", deviceHost: "build-box-2.local",
            inviterLabel: "MacBook Air", verificationCode: "482913",
            profiles: [JoinRequestProfile(profile: "claude-code", name: "builder")],
            createdAt: Date().addingTimeInterval(-240).ISO8601Format()
        ),
        JoinRequest(
            id: "jr-legacy", deviceLabel: "ci-runner", deviceHost: "ci-runner-07",
            verificationCode: nil, createdAt: Date().addingTimeInterval(-3_600).ISO8601Format()
        ),
    ]

    func listPendingJoinRequests() async throws -> [JoinRequest] { requests }

    func approveJoinRequest(id: String) async throws -> JoinApproval {
        requests.removeAll { $0.id == id }
        let json = #"{"id":"\#(id)","status":"approved","agents":[]}"#
        return try JSONDecoder().decode(JoinApproval.self, from: Data(json.utf8))
    }

    func rejectJoinRequest(id: String) async throws {
        requests.removeAll { $0.id == id }
    }
}

/// One pending Mac sign-in request for any well-formed id; approval returns a fixed code.
struct DemoSigninAPI: SigninApproving {
    func signinRequest(id: String) async throws -> SigninRequestSummary {
        let expiry = Date().addingTimeInterval(600).ISO8601Format()
        let json = #"{"request_id":"\#(id)","device_label":"Studio MacBook Pro","origin":"NL · Amsterdam","#
            + #""status":"pending","created_at":"\#(Date().ISO8601Format())","expires_at":"\#(expiry)"}"#
        return try JSONDecoder().decode(SigninRequestSummary.self, from: Data(json.utf8))
    }

    func approveSignin(id: String) async throws -> SigninApproval {
        let json = #"{"code":"306142","expires_at":"\#(Date().addingTimeInterval(540).ISO8601Format())"}"#
        return try JSONDecoder().decode(SigninApproval.self, from: Data(json.utf8))
    }

    func rejectSignin(id: String) async throws {}
}
