// Sample home dashboard payload for HIBOSS_DEMO (populated welcome / heat / projects).
// Exports: DemoHomeFixtures used by DemoBossAPI.fetchHome.
// Dependencies: HibossKit HomeDashboard. Not used in normal (server-backed) runs.

import Foundation
import HibossKit

enum DemoHomeFixtures {
    static var dashboard: HomeDashboard {
        HomeDashboard(
            boss: HomeBoss(name: "Ming"),
            kpis: HomeKPIs(
                activeSessions: 3,
                workingSessions: 2,
                pendingDecisions: 2,
                blockingPending: 1,
                unread1h: 4
            ),
            activity: HomeActivity(days: activityDays, delta: HomeActivityDelta(
                posts: 0.12, decisions: -0.5, messages: 0.03
            )),
            projects: projects,
            attention: attention
        )
    }

    private static var activityDays: [HomeActivityDay] {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        return (0..<28).compactMap { offset -> HomeActivityDay? in
            guard let day = calendar.date(byAdding: .day, value: offset - 27, to: today) else {
                return nil
            }
            let stamp = isoDay(day)
            // Deterministic-ish pattern so the heat grid looks populated in demos.
            let wave = (offset * 3 + offset % 5) % 7
            return HomeActivityDay(
                date: stamp,
                posts: wave > 4 ? wave - 3 : (wave > 2 ? 1 : 0),
                decisions: offset % 6 == 0 ? 1 : 0,
                messages: wave + (offset % 3)
            )
        }
    }

    private static let projects: [HomeProject] = [
        HomeProject(
            name: "hiboss",
            sessions: HomeProjectSessions(working: 1, waiting: 1, blocked: 0, idle: 0),
            pendingDecisions: 1,
            postCount7d: 5,
            lastPost: HomeProjectPost(
                id: "pp-1",
                body: "Shipped session transcript bubbles and scroll lock.",
                createdAt: iso(-3_600)
            ),
            lastActivityAt: iso(-600)
        ),
        HomeProject(
            name: "smart-router",
            sessions: HomeProjectSessions(working: 1, waiting: 0, blocked: 1, idle: 0),
            pendingDecisions: 1,
            postCount7d: 2,
            lastPost: HomeProjectPost(
                id: "pp-2",
                body: "Fail closed on unknown DEX classification.",
                createdAt: iso(-7_200)
            ),
            lastActivityAt: iso(-900)
        ),
        HomeProject(
            name: "payments",
            sessions: HomeProjectSessions(working: 0, waiting: 0, blocked: 0, idle: 1),
            pendingDecisions: 0,
            postCount7d: 1,
            lastPost: nil,
            lastActivityAt: iso(-86_400)
        ),
    ]

    private static let attention: [HomeAttentionItem] = [
        HomeAttentionItem(
            kind: .decision,
            messageId: "c1",
            sessionId: "sess-deploy",
            sessionLabel: "prod-release",
            project: "hiboss",
            priority: "high",
            mode: "blocking",
            body: "Ship the changelog to TestFlight tonight?",
            createdAt: iso(-120),
            expiresAt: iso(1_800)
        ),
        HomeAttentionItem(
            kind: .session,
            sessionId: "sess-pay",
            sessionLabel: "payments/hotfix",
            project: "payments",
            status: "blocked",
            statusText: "Awaiting boss reply",
            lastSeenAt: iso(-300)
        ),
        HomeAttentionItem(
            kind: .decision,
            messageId: "c2",
            sessionId: "sess-pay",
            sessionLabel: "payments/hotfix",
            project: "payments",
            priority: "normal",
            mode: "async",
            body: "Retry the failed Stripe webhook replay?",
            createdAt: iso(-900)
        ),
    ]

    private static func iso(_ offset: TimeInterval) -> String {
        Date().addingTimeInterval(offset).ISO8601Format()
    }

    private static func isoDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
