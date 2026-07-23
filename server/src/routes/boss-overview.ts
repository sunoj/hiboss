// Dashboard overview aggregate for the web console.
// Exports: getBossOverview computing KPIs, priority distribution, session
// status counts, and channel health in a single round of queries.
// Depends on D1 and the boss's accessible agent set.

import type { Env, Priority } from '../types';

export interface BossOverview {
  kpis: {
    activeSessions: number;
    workingSessions: number;
    pendingDecisions: number;
    blockingPending: number;
    unread1h: number;
  };
  priorityDistribution: Record<Priority, number>;
  sessionStatus: Record<string, number>;
  channels: { channel: string; configured: boolean }[];
}

const PRIORITIES: Priority[] = ['critical', 'high', 'normal', 'low'];
const SESSION_STATUSES = ['working', 'waiting', 'blocked', 'idle', 'completed'];

export async function getBossOverview(env: Env, agentIds: string[]): Promise<BossOverview> {
  if (agentIds.length === 0) return emptyOverview();
  const ph = agentIds.map(() => '?').join(', ');
  const now = new Date().toISOString();

  const [kpis, priorityDistribution, sessionStatus, channels] = await Promise.all([
    loadKpis(env, ph, agentIds, now),
    loadPriorityDistribution(env, ph, agentIds),
    loadSessionStatus(env, ph, agentIds),
    loadChannelHealth(env, ph, agentIds),
  ]);

  return { kpis, priorityDistribution, sessionStatus, channels };
}

async function loadKpis(
  env: Env, ph: string, agentIds: string[], now: string,
): Promise<BossOverview['kpis']> {
  const row = await env.DB.prepare(
    `SELECT
       (SELECT COUNT(*) FROM sessions WHERE agent_id IN (${ph})
          AND last_seen_at > datetime('now', '-15 minutes')) AS activeSessions,
       (SELECT COUNT(*) FROM sessions WHERE agent_id IN (${ph}) AND status = 'working'
          AND last_seen_at > datetime('now', '-15 minutes')) AS workingSessions,
       (SELECT COUNT(*) FROM messages WHERE agent_id IN (${ph})
          AND direction = 'agent_to_boss' AND status IN ('sent','delivered','read')
          AND json_extract(metadata, '$.options') IS NOT NULL
          AND (expires_at IS NULL OR expires_at > ?)) AS pendingDecisions,
       (SELECT COUNT(*) FROM messages WHERE agent_id IN (${ph})
          AND direction = 'agent_to_boss' AND status IN ('sent','delivered','read')
          AND json_extract(metadata, '$.options') IS NOT NULL AND mode = 'blocking'
          AND (expires_at IS NULL OR expires_at > ?)) AS blockingPending,
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

async function loadPriorityDistribution(
  env: Env, ph: string, agentIds: string[],
): Promise<Record<Priority, number>> {
  const rows = await env.DB.prepare(
    `SELECT priority, COUNT(*) AS c FROM messages
     WHERE agent_id IN (${ph}) AND created_at >= datetime('now', '-1 day')
     GROUP BY priority`,
  ).bind(...agentIds).all<{ priority: string; c: number }>();
  const dist = zero(PRIORITIES);
  for (const r of rows.results ?? []) {
    if ((PRIORITIES as string[]).includes(r.priority)) dist[r.priority as Priority] = r.c;
  }
  return dist;
}

async function loadSessionStatus(
  env: Env, ph: string, agentIds: string[],
): Promise<Record<string, number>> {
  const rows = await env.DB.prepare(
    `SELECT status, COUNT(*) AS c FROM sessions
     WHERE agent_id IN (${ph}) AND last_seen_at >= datetime('now', '-1 day')
     GROUP BY status`,
  ).bind(...agentIds).all<{ status: string; c: number }>();
  const counts = zero(SESSION_STATUSES);
  for (const r of rows.results ?? []) {
    counts[r.status] = r.c;
  }
  return counts;
}

async function loadChannelHealth(
  env: Env, ph: string, agentIds: string[],
): Promise<BossOverview['channels']> {
  const rows = await env.DB.prepare(
    `SELECT DISTINCT channel FROM channel_configs
     WHERE agent_id IN (${ph}) AND enabled = 1`,
  ).bind(...agentIds).all<{ channel: string }>();
  const configured = new Set((rows.results ?? []).map((r) => r.channel));
  return [
    { channel: 'discord', configured: configured.has('discord') },
    { channel: 'telegram', configured: configured.has('telegram') },
    { channel: 'api', configured: true },
  ];
}

function zero<T extends string>(keys: T[]): Record<T, number> {
  return Object.fromEntries(keys.map((k) => [k, 0])) as Record<T, number>;
}

function emptyOverview(): BossOverview {
  return {
    kpis: { activeSessions: 0, workingSessions: 0, pendingDecisions: 0, blockingPending: 0, unread1h: 0 },
    priorityDistribution: zero(PRIORITIES),
    sessionStatus: zero(SESSION_STATUSES),
    channels: [
      { channel: 'discord', configured: false },
      { channel: 'telegram', configured: false },
      { channel: 'api', configured: true },
    ],
  };
}
