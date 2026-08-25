# Home Dashboard Contract — `GET /api/boss/home`

One endpoint, one round trip, feeding the iOS Home tab (welcome header, activity card,
project cards, "needs you" list). The web console keeps using `/api/boss/overview`; this
endpoint reuses its internals but is a separate surface so the two can evolve apart.

## Scope and derivation rules

- **Agent scope**: same as every boss route — `getAccessibleAgentIds(bossId, role)`.
- **Project identity**: there is no `project` column on `sessions`. The CLI writes
  `sessions.label = "<repo>/<branch>"` (`cli/src/commands/hook.rs`) and
  `progress_posts.project = <repo basename>` (`cli/src/session.rs::project_name`). Both come
  from the same git root, so **project = `label` up to the first `/`** (a label without `/`
  is the whole label; a NULL label is skipped). Union that with `DISTINCT progress_posts.project`.
- **Horizons**: sessions count as *live* when `last_seen_at > now - 15 min` (same as
  `/sessions`); project cards look back **7 days**; the activity series is **28 days**.
- **Pending decision** = `direction = 'agent_to_boss'`, `status IN ('sent','delivered','read')`,
  `json_extract(metadata,'$.options') IS NOT NULL`, not expired — identical to `/overview`.
- All timestamps are ISO-8601 UTC strings (`normalizeTimestamp`), never SQLite's bare format.
- Query count must stay bounded (≤ 8 statements, no per-project loops) — D1 subrequest limits.

## Response

```jsonc
{
  "boss": { "name": "Ming" },                 // from bosses row; falls back to ""
  "kpis": {                                   // same semantics as /overview.kpis
    "activeSessions": 3, "workingSessions": 2,
    "pendingDecisions": 1, "blockingPending": 1, "unread1h": 4
  },
  "activity": {                               // 28 daily buckets, oldest first, UTC days
    "days": [ { "date": "2026-07-29", "posts": 2, "decisions": 1, "messages": 14 }, … ],
    "delta": { "posts": 0.12, "decisions": -0.5, "messages": 0.03 }  // (last 7d − prior 7d) / prior 7d; null when prior 7d is 0
  },
  "projects": [                               // ordered by lastActivityAt DESC, max 20
    {
      "name": "smart-router",
      "sessions": { "working": 1, "waiting": 1, "blocked": 0, "idle": 0 },  // live sessions only
      "pendingDecisions": 1,
      "postCount7d": 5,
      "lastPost": { "id": "…", "body": "Shipped X", "createdAt": "…" } | null,  // body truncated to 140 chars
      "lastActivityAt": "…"                    // max(session.last_seen_at, lastPost.createdAt)
    }
  ],
  "attention": [                              // "needs you", max 10. Tiers: blocking decisions → blocked sessions → other decisions → waiting sessions; within a tier by priority, then createdAt DESC
    {
      "kind": "decision",                     // pending decision → deep-links to MessageDetail
      "messageId": "…", "sessionId": "…" | null, "sessionLabel": "hiboss/main" | null,
      "project": "hiboss", "priority": "high", "mode": "blocking",
      "body": "…", "createdAt": "…", "expiresAt": "…" | null
    },
    {
      "kind": "session",                      // live session in waiting/blocked → deep-links to SessionMessages
      "sessionId": "…", "sessionLabel": "…", "project": "…",
      "status": "blocked", "statusText": "Awaiting boss reply" | null, "lastSeenAt": "…"
    }
  ]
}
```

Empty scope (no accessible agents) returns the same shape with zeros, 28 zero days, and
empty arrays — never 404.

## Client rules (iOS)

- Home is a **new first tab**; existing tab indices are referenced by name in
  `RootTabView` (`progressTab`, `HIBOSS_TAB`, `applyDemoRoute`, notification deep-links) and
  must all be updated together — renumbering silently broke video autoplay once.
- Loading, error, and empty states are distinct; never render "all clear" while the fetch
  failed (ios-ux-audit Theme A).
- Demo mode (`HIBOSS_DEMO=1`) must serve a populated payload from `DemoBossAPI`.
- Refresh on tab selection and on scene-active, like Progress.
