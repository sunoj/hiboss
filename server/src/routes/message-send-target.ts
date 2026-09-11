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
  targetWarning: string | null; targetSession: { id: string; label: string | null } | null;
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

export async function resolveSendTarget(c: Context<{ Bindings: Env }>, toAgent: string | null, sessionId: string | null): Promise<Response | SendTarget> {
  // Resolve targeting: try agent name/id first, then session label/id
  let targetAgentId: string | null = null;
  let targetSessionId: string | null = null;
  let direction: Direction = 'agent_to_boss';
  let targetWarning: string | null = null;
  let targetSession: { id: string; label: string | null } | null = null;
  if (toAgent) {
    // 1. Try agent by name or id prefix
    const agentTarget = await c.env.DB.prepare('SELECT id FROM api_keys WHERE name = ?')
      .bind(toAgent).first<{ id: string }>()
      ?? await c.env.DB.prepare("SELECT id FROM api_keys WHERE id LIKE ? ESCAPE '\\' LIMIT 1")
        .bind(`${escapeLike(toAgent)}%`).first<{ id: string }>();
    if (agentTarget) {
      targetAgentId = agentTarget.id;
      direction = 'agent_to_agent';
    } else {
      // Exclude the sender's own session so a colliding label can never self-target
      const sessionTargets = await findSessionTargets(c.env.DB, toAgent, sessionId);
      const matchedTargets = sessionTargets.results ?? [];
      const liveTargets = matchedTargets.filter((target) => isSessionActive(target.last_seen_at));
      const exact = (target: SessionTarget): boolean => target.label === toAgent || target.stored_label === toAgent;
      const exactTarget = matchedTargets.find((target) => exact(target) && isSessionActive(target.last_seen_at))
        ?? matchedTargets.find(exact);
      const resolvedTargets = exactTarget ? [exactTarget] : liveTargets;
      if (resolvedTargets.length > 1) {
        const candidates = resolvedTargets
          .slice(0, MAX_TARGET_CANDIDATES)
          .map(({ label, id }) => ({ label, id: id.slice(0, 8) }));
        const remaining = resolvedTargets.length - candidates.length;
        return c.json({ error: 'ambiguous_target', target: toAgent, candidates, remaining }, 409);
      }
      const sessionTarget = resolvedTargets[0] ?? matchedTargets[0];
      if (sessionTarget) {
        targetAgentId = sessionTarget.agent_id;
        targetSessionId = sessionTarget.id;
        targetSession = { id: sessionTarget.id, label: sessionTarget.label };
        direction = 'agent_to_agent';
        targetWarning = sessionWarning(sessionTarget, toAgent);
      } else {
        return missingTarget(c, toAgent, sessionId);
      }
    }
  }
  return { targetAgentId, targetSessionId, direction, targetWarning, targetSession };
}

interface SessionTarget {
  id: string; agent_id: string; label: string | null; stored_label: string | null;
  status: string | null; last_seen_at: string | null;
}

function findSessionTargets(db: D1Database, target: string, self: string | null): Promise<D1Result<SessionTarget>> {
  const prefix = `${escapeLike(target)}/%`;
  return db.prepare(`WITH targets AS (
    SELECT s.id, s.agent_id, s.label AS stored_label, ${SESSION_LABEL_SQL} AS label, s.status, s.last_seen_at
    FROM sessions s LEFT JOIN projects p ON p.id = s.project_id)
    SELECT * FROM targets WHERE (label = ? OR label LIKE ? ESCAPE '\\' OR stored_label = ? OR stored_label LIKE ? ESCAPE '\\' OR id LIKE ? ESCAPE '\\')
    AND (? IS NULL OR id != ?) ORDER BY last_seen_at DESC`)
    .bind(target, prefix, target, prefix, `${escapeLike(target)}%`, self, self).all<SessionTarget>();
}

async function missingTarget(c: Context<{ Bindings: Env }>, toAgent: string, sessionId: string | null): Promise<Response> {
  const excludeSelf = sessionId ? ' AND id != ?' : '';
  const reachableTargets = await c.env.DB
    .prepare(`SELECT id, label, last_seen_at, COUNT(*) OVER () AS total_count FROM sessions WHERE status != 'completed' AND last_seen_at > datetime('now', '-${REACHABLE_TARGET_MAX_AGE_HOURS} hours')${excludeSelf} ORDER BY CASE WHEN last_seen_at > datetime('now', '-15 minutes') THEN 0 ELSE 1 END, last_seen_at DESC LIMIT ?`)
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

function sessionWarning(sessionTarget: { status: string | null; last_seen_at: string | null }, toAgent: string): string | null {
  let targetWarning: string | null = null;
  // Warn if target session is completed or stale (>15 min)
  if (sessionTarget.status === 'completed') {
    targetWarning = `target session '${toAgent}' is completed`;
  } else if (sessionTarget.last_seen_at) {
    const lastSeen = new Date(sessionTarget.last_seen_at + 'Z').getTime();
    if (Date.now() - lastSeen > 15 * 60 * 1000) {
      targetWarning = `target session '${toAgent}' last seen ${Math.round((Date.now() - lastSeen) / 60000)}m ago`;
    }
  }
  return targetWarning;
}
