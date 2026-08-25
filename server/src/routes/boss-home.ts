// Home dashboard aggregate for the iOS Home tab.
// Exports getBossHome: KPIs, 28-day activity, project cards, and attention list.
// Depends on D1, the pending-decision predicate (same as overview), and normalizeTimestamp.

import type { Env, Mode, Priority } from '../types';
import { normalizeTimestamp } from './progress-helpers';

export interface BossHome {
  boss: { name: string };
  kpis: {
    activeSessions: number; workingSessions: number; pendingDecisions: number;
    blockingPending: number; unread1h: number;
  };
  activity: {
    days: { date: string; posts: number; decisions: number; messages: number }[];
    delta: { posts: number | null; decisions: number | null; messages: number | null };
  };
  projects: HomeProject[];
  attention: AttentionItem[];
}

interface HomeProject {
  name: string;
  sessions: { working: number; waiting: number; blocked: number; idle: number };
  pendingDecisions: number;
  postCount7d: number;
  lastPost: { id: string; body: string; createdAt: string } | null;
  lastActivityAt: string;
}

type AttentionItem =
  | {
    kind: 'decision'; messageId: string; sessionId: string | null; sessionLabel: string | null;
    project: string; priority: Priority; mode: Mode; body: string;
    createdAt: string; expiresAt: string | null;
  }
  | {
    kind: 'session'; sessionId: string; sessionLabel: string; project: string;
    status: string; statusText: string | null; lastSeenAt: string;
  };

interface LiveSession {
  id: string; label: string | null; status: string; status_text: string | null; last_seen_at: string;
}
interface PendingRow {
  id: string; session_id: string | null; body: string; priority: Priority; mode: Mode;
  created_at: string; expires_at: string | null; session_label: string | null;
}
interface ProgressRow {
  project: string; post_count: number; last_id: string; last_body: string; last_created: string;
}

const PRIORITY_RANK: Record<Priority, number> = { critical: 0, high: 1, normal: 2, low: 3 };
const SESSION_KEYS = ['working', 'waiting', 'blocked', 'idle'] as const;

/** Same pending-decision predicate as boss-overview.ts; `a` is the messages alias. */
function pendingSql(a: string): string {
  return `${a}.direction = 'agent_to_boss' AND ${a}.status IN ('sent','delivered','read')
  AND json_extract(${a}.metadata, '$.options') IS NOT NULL
  AND (${a}.expires_at IS NULL OR ${a}.expires_at > ?)`;
}

export async function getBossHome(env: Env, bossName: string, agentIds: string[]): Promise<BossHome> {
  if (agentIds.length === 0) return emptyHome(bossName);
  const ph = agentIds.map(() => '?').join(', ');
  const now = new Date().toISOString();
  const [kpis, activityRows, liveSessions, pending, progressRows] = await Promise.all([
    loadKpis(env, ph, agentIds, now),
    loadActivity(env, ph, agentIds),
    loadLiveSessions(env, ph, agentIds),
    loadPending(env, ph, agentIds, now),
    loadProgress7d(env, ph, agentIds),
  ]);
  const days = fillActivityDays(activityRows);
  return {
    boss: { name: bossName },
    kpis,
    activity: { days, delta: computeDelta(days) },
    projects: buildProjects(liveSessions, pending, progressRows),
    attention: buildAttention(liveSessions, pending),
  };
}

async function loadKpis(env: Env, ph: string, agentIds: string[], now: string): Promise<BossHome['kpis']> {
  const row = await env.DB.prepare(
    `SELECT
       (SELECT COUNT(*) FROM sessions WHERE agent_id IN (${ph})
          AND last_seen_at > datetime('now', '-15 minutes')) AS activeSessions,
       (SELECT COUNT(*) FROM sessions WHERE agent_id IN (${ph}) AND status = 'working'
          AND last_seen_at > datetime('now', '-15 minutes')) AS workingSessions,
       (SELECT COUNT(*) FROM messages WHERE agent_id IN (${ph}) AND ${pendingSql('messages')}) AS pendingDecisions,
       (SELECT COUNT(*) FROM messages WHERE agent_id IN (${ph}) AND ${pendingSql('messages')}
          AND mode = 'blocking') AS blockingPending,
       (SELECT COUNT(*) FROM messages WHERE agent_id IN (${ph})
          AND direction = 'agent_to_boss' AND status IN ('sent','delivered')
          AND created_at >= datetime('now', '-1 hour')) AS unread1h`,
  ).bind(...agentIds, ...agentIds, ...agentIds, now, ...agentIds, now, ...agentIds)
    .first<Record<string, number>>();
  return {
    activeSessions: row?.activeSessions ?? 0,
    workingSessions: row?.workingSessions ?? 0,
    pendingDecisions: row?.pendingDecisions ?? 0,
    blockingPending: row?.blockingPending ?? 0,
    unread1h: row?.unread1h ?? 0,
  };
}

async function loadActivity(env: Env, ph: string, ids: string[]): Promise<{ d: string; kind: string; c: number }[]> {
  const rows = await env.DB.prepare(
    `SELECT date(created_at) AS d, 'posts' AS kind, COUNT(*) AS c FROM progress_posts
     WHERE agent_id IN (${ph}) AND created_at >= datetime('now', '-28 days') GROUP BY d
     UNION ALL
     SELECT date(created_at), 'decisions', COUNT(*) FROM messages
     WHERE agent_id IN (${ph}) AND direction = 'agent_to_boss'
       AND json_extract(metadata, '$.options') IS NOT NULL
       AND created_at >= datetime('now', '-28 days') GROUP BY date(created_at)
     UNION ALL
     SELECT date(created_at), 'messages', COUNT(*) FROM messages
     WHERE agent_id IN (${ph}) AND created_at >= datetime('now', '-28 days')
     GROUP BY date(created_at)`,
  ).bind(...ids, ...ids, ...ids).all<{ d: string; kind: string; c: number }>();
  return rows.results ?? [];
}

async function loadLiveSessions(env: Env, ph: string, ids: string[]): Promise<LiveSession[]> {
  const rows = await env.DB.prepare(
    `SELECT id, label, status, status_text, last_seen_at FROM sessions
     WHERE agent_id IN (${ph}) AND last_seen_at > datetime('now', '-15 minutes')`,
  ).bind(...ids).all<LiveSession>();
  return rows.results ?? [];
}

async function loadPending(env: Env, ph: string, ids: string[], now: string): Promise<PendingRow[]> {
  const rows = await env.DB.prepare(
    `SELECT m.id, m.session_id, m.body, m.priority, m.mode, m.created_at, m.expires_at,
            s.label AS session_label
     FROM messages m LEFT JOIN sessions s ON s.id = m.session_id
     WHERE m.agent_id IN (${ph}) AND ${pendingSql('m')}`,
  ).bind(...ids, now).all<PendingRow>();
  return rows.results ?? [];
}

async function loadProgress7d(env: Env, ph: string, ids: string[]): Promise<ProgressRow[]> {
  const rows = await env.DB.prepare(
    `SELECT project, COUNT(*) AS post_count,
       (SELECT id FROM progress_posts x WHERE x.project = p.project AND x.agent_id IN (${ph})
          AND x.created_at >= datetime('now', '-7 days') ORDER BY x.created_at DESC LIMIT 1) AS last_id,
       (SELECT body FROM progress_posts x WHERE x.project = p.project AND x.agent_id IN (${ph})
          AND x.created_at >= datetime('now', '-7 days') ORDER BY x.created_at DESC LIMIT 1) AS last_body,
       (SELECT created_at FROM progress_posts x WHERE x.project = p.project AND x.agent_id IN (${ph})
          AND x.created_at >= datetime('now', '-7 days') ORDER BY x.created_at DESC LIMIT 1) AS last_created
     FROM progress_posts p
     WHERE p.agent_id IN (${ph}) AND p.created_at >= datetime('now', '-7 days')
     GROUP BY p.project`,
  ).bind(...ids, ...ids, ...ids, ...ids).all<ProgressRow>();
  return rows.results ?? [];
}

function projectFromLabel(label: string | null | undefined): string | null {
  if (!label) return null;
  const i = label.indexOf('/');
  return i === -1 ? label : label.slice(0, i);
}

function maxTs(a: string | null, b: string | null): string | null {
  if (!a) return b;
  if (!b) return a;
  return a >= b ? a : b;
}

function buildProjects(sessions: LiveSession[], pending: PendingRow[], progress: ProgressRow[]): HomeProject[] {
  type Acc = {
    sessions: HomeProject['sessions']; pendingDecisions: number; postCount7d: number;
    lastPost: HomeProject['lastPost']; lastActivityAt: string | null;
  };
  const map = new Map<string, Acc>();
  const ensure = (name: string): Acc => {
    let row = map.get(name);
    if (!row) {
      row = { sessions: { working: 0, waiting: 0, blocked: 0, idle: 0 }, pendingDecisions: 0, postCount7d: 0, lastPost: null, lastActivityAt: null };
      map.set(name, row);
    }
    return row;
  };
  for (const s of sessions) {
    const name = projectFromLabel(s.label);
    if (!name) continue;
    const row = ensure(name);
    if ((SESSION_KEYS as readonly string[]).includes(s.status)) {
      row.sessions[s.status as typeof SESSION_KEYS[number]] += 1;
    }
    row.lastActivityAt = maxTs(row.lastActivityAt, normalizeTimestamp(s.last_seen_at));
  }
  for (const p of progress) {
    const row = ensure(p.project);
    row.postCount7d = p.post_count;
    const body = p.last_body.length <= 140 ? p.last_body : p.last_body.slice(0, 140);
    row.lastPost = { id: p.last_id, body, createdAt: normalizeTimestamp(p.last_created) };
    row.lastActivityAt = maxTs(row.lastActivityAt, normalizeTimestamp(p.last_created));
  }
  for (const d of pending) {
    const name = projectFromLabel(d.session_label);
    if (!name) continue;
    const row = ensure(name);
    row.pendingDecisions += 1;
    row.lastActivityAt = maxTs(row.lastActivityAt, normalizeTimestamp(d.created_at));
  }
  return [...map.entries()]
    .map(([name, row]) => ({
      name, sessions: row.sessions, pendingDecisions: row.pendingDecisions,
      postCount7d: row.postCount7d, lastPost: row.lastPost,
      lastActivityAt: row.lastActivityAt ?? new Date(0).toISOString(),
    }))
    .sort((a, b) => b.lastActivityAt.localeCompare(a.lastActivityAt))
    .slice(0, 20);
}

function buildAttention(sessions: LiveSession[], pending: PendingRow[]): AttentionItem[] {
  type Ranked = { tier: number; priority: number; createdAt: string; item: AttentionItem };
  const ranked: Ranked[] = [];
  for (const d of pending) {
    ranked.push({
      tier: d.mode === 'blocking' ? 0 : 2,
      priority: PRIORITY_RANK[d.priority] ?? 2,
      createdAt: d.created_at,
      item: {
        kind: 'decision', messageId: d.id, sessionId: d.session_id, sessionLabel: d.session_label,
        project: projectFromLabel(d.session_label) ?? '', priority: d.priority, mode: d.mode,
        body: d.body, createdAt: normalizeTimestamp(d.created_at),
        expiresAt: d.expires_at ? normalizeTimestamp(d.expires_at) : null,
      },
    });
  }
  for (const s of sessions) {
    if (s.status !== 'waiting' && s.status !== 'blocked') continue;
    const label = s.label ?? '';
    ranked.push({
      tier: s.status === 'blocked' ? 1 : 3,
      priority: 2,
      createdAt: s.last_seen_at,
      item: {
        kind: 'session', sessionId: s.id, sessionLabel: label,
        project: projectFromLabel(label) ?? '', status: s.status,
        statusText: s.status_text, lastSeenAt: normalizeTimestamp(s.last_seen_at),
      },
    });
  }
  ranked.sort((a, b) =>
    a.tier - b.tier || a.priority - b.priority || b.createdAt.localeCompare(a.createdAt));
  return ranked.slice(0, 10).map((r) => r.item);
}

function fillActivityDays(rows: { d: string; kind: string; c: number }[]): BossHome['activity']['days'] {
  const days = emptyDays();
  const byDate = new Map(days.map((d) => [d.date, d]));
  for (const r of rows) {
    const bucket = byDate.get(r.d);
    if (!bucket) continue;
    if (r.kind === 'posts') bucket.posts = r.c;
    else if (r.kind === 'decisions') bucket.decisions = r.c;
    else if (r.kind === 'messages') bucket.messages = r.c;
  }
  return days;
}

function emptyDays(): BossHome['activity']['days'] {
  const out: BossHome['activity']['days'] = [];
  const today = new Date();
  today.setUTCHours(0, 0, 0, 0);
  for (let i = 27; i >= 0; i--) {
    const d = new Date(today);
    d.setUTCDate(today.getUTCDate() - i);
    out.push({ date: d.toISOString().slice(0, 10), posts: 0, decisions: 0, messages: 0 });
  }
  return out;
}

function computeDelta(days: BossHome['activity']['days']): BossHome['activity']['delta'] {
  const sum = (slice: typeof days, key: 'posts' | 'decisions' | 'messages') =>
    slice.reduce((n, d) => n + d[key], 0);
  const last7 = days.slice(-7);
  const prior7 = days.slice(-14, -7);
  const ratio = (last: number, prior: number): number | null =>
    prior === 0 ? null : (last - prior) / prior;
  return {
    posts: ratio(sum(last7, 'posts'), sum(prior7, 'posts')),
    decisions: ratio(sum(last7, 'decisions'), sum(prior7, 'decisions')),
    messages: ratio(sum(last7, 'messages'), sum(prior7, 'messages')),
  };
}

function emptyHome(bossName: string): BossHome {
  return {
    boss: { name: bossName },
    kpis: { activeSessions: 0, workingSessions: 0, pendingDecisions: 0, blockingPending: 0, unread1h: 0 },
    activity: { days: emptyDays(), delta: { posts: null, decisions: null, messages: null } },
    projects: [],
    attention: [],
  };
}
