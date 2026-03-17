// Router for session registration, discovery, and heartbeat.
// Exports sessionsRouter mounted at /api/sessions.
// Depends on Hono, auth middleware, and Env types.

import { Hono } from 'hono';
import type { Env } from '../types';
import { apiAuth, getAgentId } from '../middleware/auth';

const STALE_MINUTES = 15;

const routes = new Hono<{ Bindings: Env }>({});
routes.use('*', apiAuth);

interface SessionRow {
  id: string;
  agent_id: string;
  label: string | null;
  branch: string | null;
  cwd: string | null;
  started_at: string;
  last_seen_at: string;
}

// POST /api/sessions — register or update a session
routes.post('/', async (c) => {
  const agentId = getAgentId(c);
  const payload = await c.req.json<Record<string, unknown>>();
  const id = typeof payload.id === 'string' ? payload.id.trim() : '';
  if (!id) return c.text('id is required', 400);
  const branch = typeof payload.branch === 'string' ? payload.branch.trim() || null : null;
  const cwd = typeof payload.cwd === 'string' ? payload.cwd.trim() || null : null;
  const label = typeof payload.label === 'string' ? payload.label.trim() || null : (cwd && branch ? `${cwd}/${branch}` : cwd ?? branch);
  // Upsert: insert or update on conflict
  await c.env.DB
    .prepare(
      `INSERT INTO sessions (id, agent_id, label, branch, cwd) VALUES (?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET label = excluded.label, branch = excluded.branch, cwd = excluded.cwd, last_seen_at = datetime('now')`
    )
    .bind(id, agentId, label, branch, cwd)
    .run();
  return c.json({ id, label, branch, cwd }, 201);
});

// GET /api/sessions — list active sessions (within STALE_MINUTES)
routes.get('/', async (c) => {
  const agentId = getAgentId(c);
  const allAgents = c.req.query('all') === 'true';
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

// PATCH /api/sessions/:id — heartbeat (update last_seen_at)
routes.patch('/:id', async (c) => {
  const agentId = getAgentId(c);
  const result = await c.env.DB
    .prepare("UPDATE sessions SET last_seen_at = datetime('now') WHERE id = ? AND agent_id = ?")
    .bind(c.req.param('id'), agentId)
    .run();
  if (!result.meta.changed_db) return c.text('not found', 404);
  return c.json({ ok: true });
});

// DELETE /api/sessions/:id — deregister
routes.delete('/:id', async (c) => {
  const agentId = getAgentId(c);
  await c.env.DB
    .prepare('DELETE FROM sessions WHERE id = ? AND agent_id = ?')
    .bind(c.req.param('id'), agentId)
    .run();
  return c.json({ ok: true });
});

export const sessionsRouter = routes;
