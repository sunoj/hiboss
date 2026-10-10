// Resolves agent/session targets while preserving legacy ambiguity and activity checks.
// Exports resolveSendTarget; depends on Hono context and D1 sessions.
import type { Context } from 'hono';
import type { Env, Direction } from '../types';
import { SESSION_LABEL_SQL } from '../projects/session-label';
const MAX_TARGET_CANDIDATES = 10;
const TARGET_ACTIVITY_WINDOW_MS = 15 * 60 * 1000;
const REACHABLE_TARGET_MAX_AGE_HOURS = 24;
export interface SendTarget {
  targetAgentId: string | null; targetSessionId: string | null; direction: Direction;
  targetWarning: string | null;
  targetSession: { id: string; label: string | null; nickname: string | null } | null;
}
function escapeLike(value: string): string {
  return value.replace(/[%_\\]/g, '\\$&');
}

function isSessionActive(lastSeenAt: string | null): boolean {
  if (!lastSeenAt) return false;
  const lastSeen = new Date(`${lastSeenAt}Z`).getTime();
  return Number.isFinite(lastSeen) && Date.now() - lastSeen < TARGET_ACTIVITY_WINDOW_MS;
}

function sessionIdleMinutes(lastSeenAt: string | null): number | null {
  if (!lastSeenAt) return null;
  const lastSeen = new Date(`${lastSeenAt}Z`).getTime();
  if (!Number.isFinite(lastSeen)) return null;
  return Math.max(0, Math.round((Date.now() - lastSeen) / 60000));
}

export async function resolveSendTarget(
  c: Context<{ Bindings: Env }>, toAgent: string | null, sessionId: string | null,
): Promise<Response | SendTarget> {
  if (!toAgent) return {
    targetAgentId: null, targetSessionId: null, direction: 'agent_to_boss',
    targetWarning: null, targetSession: null,
  };
  // An agent name always wins, so no label or nickname can redirect it; exact session
  // names then beat id prefixes, which a short nickname could otherwise collide with.
  const named = await c.env.DB.prepare('SELECT id FROM api_keys WHERE name = ?')
    .bind(toAgent).first<{ id: string }>();
  const exact = named ? null : await findExactSessionTarget(c.env.DB, toAgent, sessionId);
  if (exact) return sessionSendTarget(exact, toAgent);
  const agentTarget = named
    ?? await c.env.DB.prepare("SELECT id FROM api_keys WHERE id LIKE ? ESCAPE '\\' LIMIT 1")
      .bind(`${escapeLike(toAgent)}%`).first<{ id: string }>();
  if (agentTarget) return {
    targetAgentId: agentTarget.id, targetSessionId: null, direction: 'agent_to_agent',
    targetWarning: null, targetSession: null,
  };
  const { results: matchedTargets } = await findSessionTargets(c.env.DB, toAgent, sessionId);
  const liveTargets = matchedTargets.filter(target => isSessionActive(target.last_seen_at));
  if (liveTargets.length > 1) {
    const candidates = liveTargets.slice(0, MAX_TARGET_CANDIDATES)
      .map(({ label, id }) => ({ label, id: id.slice(0, 8) }));
    const remaining = liveTargets.length - candidates.length;
    return c.json({ error: 'ambiguous_target', target: toAgent, candidates, remaining }, 409);
  }
  const target = liveTargets[0] ?? matchedTargets[0];
  return target ? sessionSendTarget(target, toAgent) : missingTarget(c, toAgent, sessionId);
}

interface SessionTarget {
  id: string; agent_id: string; label: string | null; stored_label: string | null;
  nickname: string | null;
  status: string | null; last_seen_at: string | null;
}

const TARGET_SELECT = `SELECT s.id, s.agent_id, s.label AS stored_label, s.nickname,
  ${SESSION_LABEL_SQL} AS label, s.status, s.last_seen_at
  FROM sessions s LEFT JOIN projects p ON p.id = s.project_id`;

async function findExactSessionTarget(
  db: D1Database, target: string, self: string | null,
): Promise<SessionTarget | null> {
  const label = await db.prepare(`${TARGET_SELECT}
    WHERE (${SESSION_LABEL_SQL} = ? OR s.label = ?) AND (? IS NULL OR s.id <> ?)
    ORDER BY s.last_seen_at > datetime('now', '-15 minutes') DESC, s.last_seen_at DESC LIMIT 1`)
    .bind(target, target, self, self).first<SessionTarget>();
  if (label) return label;
  return db.prepare(`${TARGET_SELECT}
    WHERE s.nickname = ? AND s.id <> ? AND s.status <> 'completed'
      AND s.last_seen_at > datetime('now', '-24 hours')
      AND s.project_id = (SELECT project_id FROM sessions WHERE id = ?)
    ORDER BY s.last_seen_at DESC LIMIT 1`)
    .bind(target, self, self).first<SessionTarget>();
}

function sessionSendTarget(target: SessionTarget, requested: string): SendTarget {
  return {
    targetAgentId: target.agent_id, targetSessionId: target.id, direction: 'agent_to_agent',
    targetWarning: sessionWarning(target, requested),
    targetSession: { id: target.id, label: target.label, nickname: target.nickname },
  };
}

function findSessionTargets(
  db: D1Database, target: string, self: string | null,
): Promise<D1Result<SessionTarget>> {
  const prefix = `${escapeLike(target)}/%`;
  return db.prepare(`WITH targets AS (
    ${TARGET_SELECT})
    SELECT * FROM targets WHERE (label = ? OR label LIKE ? ESCAPE '\\' OR stored_label = ?
      OR stored_label LIKE ? ESCAPE '\\' OR id LIKE ? ESCAPE '\\')
    AND (? IS NULL OR id != ?) ORDER BY last_seen_at DESC`)
    .bind(target, prefix, target, prefix, `${escapeLike(target)}%`, self, self).all<SessionTarget>();
}

async function missingTarget(
  c: Context<{ Bindings: Env }>, toAgent: string, sessionId: string | null,
): Promise<Response> {
  const excludeSelf = sessionId ? ' AND id != ?' : '';
  const reachableTargets = await c.env.DB
    .prepare(`SELECT id, label, last_seen_at, COUNT(*) OVER () AS total_count FROM sessions
      WHERE status != 'completed'
        AND last_seen_at > datetime('now', '-${REACHABLE_TARGET_MAX_AGE_HOURS} hours')${excludeSelf}
      ORDER BY CASE WHEN last_seen_at > datetime('now', '-15 minutes') THEN 0 ELSE 1 END,
        last_seen_at DESC LIMIT ?`)
    .bind(...(sessionId ? [sessionId, MAX_TARGET_CANDIDATES] : [MAX_TARGET_CANDIDATES]))
    .all<{ id: string; label: string | null; last_seen_at: string | null; total_count: number }>();
  const targets = reachableTargets.results ?? [];
  const candidates = targets.map(({ label, id, last_seen_at }) => {
    const idleMinutes = sessionIdleMinutes(last_seen_at);
    return {
      label,
      id: id.slice(0, 8),
      ...(idleMinutes !== null && !isSessionActive(last_seen_at) ? { idle_minutes: idleMinutes } : {}),
    };
  });
  const remaining = Math.max((targets[0]?.total_count ?? 0) - candidates.length, 0);
  return c.json({ error: 'target_not_found', target: toAgent, candidates, remaining }, 404);
}

function sessionWarning(
  sessionTarget: { status: string | null; last_seen_at: string | null }, toAgent: string,
): string | null {
  let targetWarning: string | null = null;
  // Warn if target session is completed or stale (>15 min)
  if (sessionTarget.status === 'completed') {
    targetWarning = `target session '${toAgent}' is completed`;
  } else if (sessionTarget.last_seen_at) {
    const lastSeen = new Date(sessionTarget.last_seen_at + 'Z').getTime();
    if (Date.now() - lastSeen > 15 * 60 * 1000) {
      const minutes = Math.round((Date.now() - lastSeen) / 60000);
      targetWarning = `target session '${toAgent}' last seen ${minutes}m ago`;
    }
  }
  return targetWarning;
}
