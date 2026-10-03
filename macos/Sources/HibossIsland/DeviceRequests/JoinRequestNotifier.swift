// Local notifications for machines asking to join; one per request ID the model announces.
// Exports: JoinRequestNotice, JoinRequestNotifying, and JoinRequestNotifier.
// Dependencies: UserNotifications, HibossKit JoinRequest, and SystemMessageNotificationCenter.

import HibossKit
import UserNotifications

struct JoinRequestNotice: Equatable, Sendable {
    static let userInfoKey = "joinRequestID"
    let requestID: String
    let title: String
    let body: String

    /// Mirrors the APNs copy: `mini (claude, codex) · code 012345`.
    init(request: JoinRequest) {
        requestID = request.id
        title = L("New device wants to join")
        let device = request.profiles.isEmpty
            ? request.deviceLabel : "\(request.deviceLabel) (\(request.profileSummary))"
        body = request.displayCode.map { L("\(device) · code \($0)") } ?? device
    }
}

@MainActor
protocol JoinRequestNotifying: AnyObject {
    func postJoinRequest(_ notice: JoinRequestNotice) async throws
}

/// Deduplication lives in `JoinRequestsModel.onNewRequests`; this only checks permission and posts.
@MainActor
final class JoinRequestNotifier {
    private let center: any JoinRequestNotifying
    private let isAuthorized: @MainActor () async -> Bool

    init(center: any JoinRequestNotifying, isAuthorized: @escaping @MainActor () async -> Bool) {
        self.center = center
        self.isAuthorized = isAuthorized
    }

    func announce(_ requests: [JoinRequest]) async {
        guard !requests.isEmpty, await isAuthorized() else { return }
        for request in requests {
            try? await center.postJoinRequest(JoinRequestNotice(request: request))
        }
    }
}

extension SystemMessageNotificationCenter: JoinRequestNotifying {
    func postJoinRequest(_ notice: JoinRequestNotice) async throws {
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.sound = .default
        content.userInfo = [JoinRequestNotice.userInfoKey: notice.requestID]
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "join-request-" + notice.requestID, content: content, trigger: nil
        ))
    }
}
