// Home dashboard domain models for GET /api/boss/home.
// Exports: HomeDashboard and nested types, plus HomeServing.
// Dependencies: Foundation Codable. Wire format is docs/home-dashboard-contract.md.

import Foundation

public struct HomeDashboard: Codable, Equatable, Sendable {
    public let boss: HomeBoss
    public let kpis: HomeKPIs
    public let activity: HomeActivity
    public let projects: [HomeProject]
    public let attention: [HomeAttentionItem]

    public init(
        boss: HomeBoss,
        kpis: HomeKPIs,
        activity: HomeActivity,
        projects: [HomeProject] = [],
        attention: [HomeAttentionItem] = []
    ) {
        self.boss = boss
        self.kpis = kpis
        self.activity = activity
        self.projects = projects
        self.attention = attention
    }
}

public struct HomeBoss: Codable, Equatable, Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

public struct HomeKPIs: Codable, Equatable, Sendable {
    public let activeSessions: Int
    public let workingSessions: Int
    public let pendingDecisions: Int
    public let blockingPending: Int
    public let unread1h: Int

    public init(
        activeSessions: Int,
        workingSessions: Int,
        pendingDecisions: Int,
        blockingPending: Int,
        unread1h: Int
    ) {
        self.activeSessions = activeSessions
        self.workingSessions = workingSessions
        self.pendingDecisions = pendingDecisions
        self.blockingPending = blockingPending
        self.unread1h = unread1h
    }
}

public struct HomeActivity: Codable, Equatable, Sendable {
    public let days: [HomeActivityDay]
    public let delta: HomeActivityDelta

    public init(days: [HomeActivityDay], delta: HomeActivityDelta) {
        self.days = days
        self.delta = delta
    }
}

public struct HomeActivityDay: Codable, Equatable, Sendable, Identifiable {
    public var id: String { date }

    public let date: String
    public let posts: Int
    public let decisions: Int
    public let messages: Int

    public init(date: String, posts: Int, decisions: Int, messages: Int) {
        self.date = date
        self.posts = posts
        self.decisions = decisions
        self.messages = messages
    }

    /// Combined signal for heat-grid intensity.
    public var total: Int { posts + decisions + messages }
}

public struct HomeActivityDelta: Codable, Equatable, Sendable {
    /// Relative change vs prior 7d; null when prior window was zero.
    public let posts: Double?
    public let decisions: Double?
    public let messages: Double?

    public init(posts: Double?, decisions: Double?, messages: Double?) {
        self.posts = posts
        self.decisions = decisions
        self.messages = messages
    }
}

public struct HomeProject: Codable, Equatable, Sendable, Identifiable {
    public var id: String { name }

    public let name: String
    public let sessions: HomeProjectSessions
    public let pendingDecisions: Int
    public let postCount7d: Int
    public let lastPost: HomeProjectPost?
    public let lastActivityAt: String

    public init(
        name: String,
        sessions: HomeProjectSessions,
        pendingDecisions: Int,
        postCount7d: Int,
        lastPost: HomeProjectPost?,
        lastActivityAt: String
    ) {
        self.name = name
        self.sessions = sessions
        self.pendingDecisions = pendingDecisions
        self.postCount7d = postCount7d
        self.lastPost = lastPost
        self.lastActivityAt = lastActivityAt
    }
}

public struct HomeProjectSessions: Codable, Equatable, Sendable {
    public let working: Int
    public let waiting: Int
    public let blocked: Int
    public let idle: Int

    public init(working: Int, waiting: Int, blocked: Int, idle: Int) {
        self.working = working
        self.waiting = waiting
        self.blocked = blocked
        self.idle = idle
    }

    public var liveTotal: Int { working + waiting + blocked + idle }
}

public struct HomeProjectPost: Codable, Equatable, Sendable {
    public let id: String
    public let body: String
    public let createdAt: String

    public init(id: String, body: String, createdAt: String) {
        self.id = id
        self.body = body
        self.createdAt = createdAt
    }
}

public enum HomeAttentionKind: String, Codable, Sendable {
    case decision
    case session
}

/// Discriminated "needs you" row. Decision and session fields are optional so
/// a single Codable type covers both contract variants without an enum payload.
public struct HomeAttentionItem: Codable, Equatable, Sendable, Identifiable {
    public var id: String {
        switch kind {
        case .decision: return "decision:\(messageId ?? "")"
        case .session: return "session:\(sessionId ?? "")"
        }
    }

    public let kind: HomeAttentionKind
    public let messageId: String?
    public let sessionId: String?
    public let sessionLabel: String?
    public let project: String
    public let priority: String?
    public let mode: String?
    public let body: String?
    public let createdAt: String?
    public let expiresAt: String?
    public let status: String?
    public let statusText: String?
    public let lastSeenAt: String?

    public init(
        kind: HomeAttentionKind,
        messageId: String? = nil,
        sessionId: String? = nil,
        sessionLabel: String? = nil,
        project: String,
        priority: String? = nil,
        mode: String? = nil,
        body: String? = nil,
        createdAt: String? = nil,
        expiresAt: String? = nil,
        status: String? = nil,
        statusText: String? = nil,
        lastSeenAt: String? = nil
    ) {
        self.kind = kind
        self.messageId = messageId
        self.sessionId = sessionId
        self.sessionLabel = sessionLabel
        self.project = project
        self.priority = priority
        self.mode = mode
        self.body = body
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.status = status
        self.statusText = statusText
        self.lastSeenAt = lastSeenAt
    }
}

public protocol HomeServing: Sendable {
    func fetchHome() async throws -> HomeDashboard
}
