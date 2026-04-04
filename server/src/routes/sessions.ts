// Router for session registration, discovery, and heartbeat.
// Exports sessionsRouter mounted at /api/sessions.
// Depends on Hono, auth middleware, and Env types.

import { Hono } from 'hono';
import type { Env } from '../types';
import { dualAuth, getAgentId, isBossAuth } from '../middleware/auth';

const STALE_MINUTES = 15;

const routes = new Hono<{ Bindings: Env }>({});
routes.use('*', dualAuth);

type SessionStatus = 'working' | 'blocked' | 'waiting' | 'idle' | 'completed';
const SESSION_STATUSES: SessionStatus[] = ['working', 'blocked', 'waiting', 'idle', 'completed'];

interface SessionRow {
  id: string;
  agent_id: string;
  label: string | null;
  branch: string | null;
  cwd: string | null;
  status: SessionStatus;
  status_text: string | null;
  discord_thread_id: string | null;
  telegram_topic_id: number | null;
  started_at: string;
  last_seen_at: string;
}

// POST /api/sessions — register or update a session
routes.post('/', async (c) => {
  if (isBossAuth(c)) return c.text('agent required', 403);
  const agentId = getAgentId(c);
  const payload = await c.req.json<Record<string, unknown>>();
  const id = typeof payload.id === 'string' ? payload.id.trim() : '';
  if (!id) return c.text('id is required', 400);
  const branch = typeof payload.branch === 'string' ? payload.branch.trim() || null : null;
  const cwd = typeof payload.cwd === 'string' ? payload.cwd.trim() || null : null;
  const label = typeof payload.label === 'string' ? payload.label.trim() || null : (cwd && branch ? `${cwd}/${branch}` : cwd ?? branch);
  const rawStatus = typeof payload.status === 'string' ? payload.status.trim() : '';
  const status: SessionStatus = SESSION_STATUSES.includes(rawStatus as SessionStatus) ? (rawStatus as SessionStatus) : 'working';
  const statusText = typeof payload.status_text === 'string' ? payload.status_text.trim() || null : null;
  // Upsert: insert or update on conflict
  const result = await c.env.DB
    .prepare(
      `INSERT INTO sessions (id, agent_id, label, branch, cwd, status, status_text) VALUES (?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET label = excluded.label, branch = excluded.branch, cwd = excluded.cwd, status = excluded.status, status_text = excluded.status_text, last_seen_at = datetime('now')
       WHERE sessions.agent_id = excluded.agent_id
       RETURNING id`
    )
    .bind(id, agentId, label, branch, cwd, status, statusText)
    .first<{ id: string }>();
  if (!result) {
    const existing = await c.env.DB.prepare('SELECT agent_id FROM sessions WHERE id = ?').bind(id).first<{ agent_id: string }>();
    if (existing && existing.agent_id !== agentId) {
      return c.text('session belongs to another agent', 409);
    }
    return c.text('failed to persist session', 500);
  }
  return c.json({ id, label, branch, cwd, status, status_text: statusText }, 201);
});

// GET /api/sessions — list active sessions (within STALE_MINUTES)
routes.get('/', async (c) => {
  const bossRequest = isBossAuth(c);
  const agentId = bossRequest ? null : getAgentId(c);
  const allAgents = bossRequest && c.req.query('all') === 'true';
  const where = allAgents
    ? `last_seen_at > datetime('now', '-${STALE_MINUTES} minutes')`
    : `agent_id = ? AND last_seen_at > datetime('now', '-${STALE_MINUTES} minutes')`;
  const binds = allAgents ? [] : [agentId];
  const rows = await c.env.DB
    .prepare(`SELECT sessions.*, api_keys.name AS agent_name FROM sessions LEFT JOIN api_keys ON api_keys.id = sessions.agent_id WHERE ${where} ORDER BY last_seen_at DESC`)
    .bind(...binds)
    .all<SessionRow & { agent_name: string }>();
  return c.json({ sessions: rows.results ?? [] });
});

// PATCH /api/sessions/:id — heartbeat with optional status update
routes.patch('/:id', async (c) => {
  if (isBossAuth(c)) return c.text('agent required', 403);
  const agentId = getAgentId(c);
  const contentType = c.req.header('content-type') || '';
  let status: SessionStatus | undefined;
  let statusText: string | null | undefined;
  if (contentType.includes('application/json')) {
    const payload = await c.req.json<Record<string, unknown>>();
    const rawStatus = typeof payload.status === 'string' ? payload.status.trim() : '';
    if (rawStatus && SESSION_STATUSES.includes(rawStatus as SessionStatus)) {
      status = rawStatus as SessionStatus;
    }
    if ('status_text' in payload) {
      statusText = typeof payload.status_text === 'string' ? payload.status_text.trim() || null : null;
    }
  }
  const sets = ["last_seen_at = datetime('now')"];
  const binds: (string | null)[] = [];
  if (status) { sets.push('status = ?'); binds.push(status); }
  if (statusText !== undefined) { sets.push('status_text = ?'); binds.push(statusText); }
  binds.push(c.req.param('id'), agentId);
  const result = await c.env.DB
    .prepare(`UPDATE sessions SET ${sets.join(', ')} WHERE id = ? AND agent_id = ?`)
    .bind(...binds)
    .run();
  if (!result.meta.changed_db) return c.text('not found', 404);
  return c.json({ ok: true });
});

// DELETE /api/sessions/:id — deregister
routes.delete('/:id', async (c) => {
  if (isBossAuth(c)) return c.text('agent required', 403);
  const agentId = getAgentId(c);
  await c.env.DB
    .prepare('UPDATE sessions SET telegram_topic_id = NULL WHERE id = ? AND agent_id = ?')
    .bind(c.req.param('id'), agentId)
    .run();
  await c.env.DB
    .prepare('DELETE FROM sessions WHERE id = ? AND agent_id = ?')
    .bind(c.req.param('id'), agentId)
    .run();
  return c.json({ ok: true });
});

export const sessionsRouter = routes;
