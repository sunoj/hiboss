// Source-specific escalation copy shared by compact refresh rows and native pending notices.
// Exports PendingNoticeSource; resolves English and Simplified Chinese package resources.
// Dependencies: Foundation localization and HibossKit's resource bundle.

import Foundation

public enum PendingNoticeSource: CaseIterable, Sendable {
    case requests, panels, questionnaires, messages, transcript, preferences, deviceRequests
    case progress, connection, display, submission, refresh

    public var slowTitle: String {
        switch self {
        case .requests: kitL("Requests are taking longer than expected.")
        case .panels: kitL("Panels are taking longer than expected.")
        case .questionnaires: kitL("Questionnaires are taking longer than expected.")
        case .messages: kitL("Messages are taking longer than expected.")
        case .transcript: kitL("Transcript is taking longer than expected.")
        case .preferences: kitL("Preferences are taking longer than expected.")
        case .deviceRequests: kitL("Device requests are taking longer than expected.")
        case .progress: kitL("Progress is taking longer than expected.")
        case .connection: kitL("Connection is taking longer than expected.")
        case .display: kitL("Display is taking longer than expected.")
        case .submission: kitL("Submission receipt is taking longer than expected.")
        case .refresh: kitL("Refresh is taking longer than expected.")
        }
    }
}
