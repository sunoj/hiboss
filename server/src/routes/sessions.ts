// Router for session registration, discovery, and heartbeat.
// Exports sessionsRouter mounted at /api/sessions.
// Depends on Hono, auth middleware, and Env types.

import { parseProject, resolveProject } from '../projects';
import { SESSION_LABEL_SQL, mapSessionProject, type SessionProjectRow } from '../projects/session-label';
import { isRecord } from './progress-helpers';
import { Hono } from 'hono';
import type { Env } from '../types';
import { dualAuth, getAgentId, getBossId, getBossRole, isBossAuth } from '../middleware/auth';
import { getAccessibleAgentIds } from './boss-api';

const STALE_MINUTES = 15;

const routes = new Hono<{ Bindings: Env }>({});
routes.use('*', dualAuth);

type SessionStatus = 'working' | 'blocked' | 'waiting' | 'idle' | 'completed';
const SESSION_STATUSES: SessionStatus[] = ['working', 'blocked', 'waiting', 'idle', 'completed'];

interface SessionRow {
  id: string;
  agent_id: string;
  project_id: string | null;
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
  const payload = await c.req.json<unknown>().catch(() => null);
  if (!isRecord(payload)) return c.text('session body must be an object', 400);
  const id = typeof payload.id === 'string' ? payload.id.trim() : '';
  if (!id) return c.text('id is required', 400);
  const branch = typeof payload.branch === 'string' ? payload.branch.trim() || null : null;
  const cwd = typeof payload.cwd === 'string' ? payload.cwd.trim() || null : null;
  let label = typeof payload.label === 'string' ? payload.label.trim() || null : (cwd && branch ? `${cwd}/${branch}` : cwd ?? branch);
  const rawStatus = typeof payload.status === 'string' ? payload.status.trim() : '';
  const status: SessionStatus = SESSION_STATUSES.includes(rawStatus as SessionStatus) ? (rawStatus as SessionStatus) : 'working';
  const statusText = typeof payload.status_text === 'string' ? payload.status_text.trim() || null : null;
  const input = parseProject(payload.project_identity ?? payload.project ?? (typeof payload.label === 'string' ? payload.label.split('/')[0] : cwd?.replace(/\/+$/, '').split('/').pop()));
  if (typeof input === 'string') return c.text(input, 400);
  const owner = await c.env.DB.prepare('SELECT s.agent_id, p.id, p.slug FROM sessions s LEFT JOIN projects p ON p.id = s.project_id WHERE s.id = ?').bind(id).first<{ agent_id: string; id: import('../projects').ProjectId | null; slug: string | null }>();
  if (owner && owner.agent_id !== agentId) return c.text('session belongs to another agent', 409);
  const resolved = input ? await resolveProject(c.env.DB, input, agentId, payload.project_identity || payload.project ? 'explicit' : 'label') : null;
  if (resolved && !resolved.ok) return c.text(resolved.error, 409);
  const project = resolved?.ok ? resolved.project : (owner?.id && owner.slug ? { id: owner.id, slug: owner.slug } : null);
  if (!project) return c.text('project is required', 400);
  if (project && (payload.project_identity !== undefined || payload.project !== undefined || !label)) label = branch ? `${project.slug}/${branch}` : (label?.includes('/') ? `${project.slug}/${label.split('/').slice(1).join('/')}` : project.slug);
  // Upsert: insert or update on conflict
  const result = await c.env.DB
    .prepare(
      `INSERT INTO sessions (id, agent_id, label, branch, cwd, status, status_text, project_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET project_id = COALESCE(excluded.project_id, sessions.project_id), label = excluded.label, branch = excluded.branch, cwd = excluded.cwd, status = excluded.status, status_text = excluded.status_text, last_seen_at = datetime('now')
       WHERE sessions.agent_id = excluded.agent_id
       RETURNING id`
    )
    .bind(id, agentId, label, branch, cwd, status, statusText, project.id)
    .first<{ id: string }>();
  if (!result) {
    const existing = await c.env.DB.prepare('SELECT agent_id FROM sessions WHERE id = ?').bind(id).first<{ agent_id: string }>();
    if (existing && existing.agent_id !== agentId) {
      return c.text('session belongs to another agent', 409);
    }
    return c.text('failed to persist session', 500);
  }
  const displayName = await c.env.DB.prepare('SELECT display_name FROM projects WHERE id = ?').bind(project.id).first<string>('display_name');
  return c.json(mapSessionProject({ id, label, branch, cwd, status, status_text: statusText, project_id: project.id, project_slug: project.slug, project_display_name: displayName }), 201);
});

// GET /api/sessions — list active sessions (within STALE_MINUTES)
routes.get('/', async (c) => {
  // The legacy all parameter is accepted but never expands the caller's scope.
  const agentIds = isBossAuth(c)
    ? await getAccessibleAgentIds(c.env, getBossId(c), getBossRole(c))
    : [getAgentId(c)];
  if (agentIds.length === 0) return c.json({ sessions: [] });
  const placeholders = agentIds.map(() => '?').join(', ');
  const where = `s.agent_id IN (${placeholders}) AND last_seen_at > datetime('now', '-${STALE_MINUTES} minutes')`;
  const rows = await c.env.DB
    .prepare(`SELECT s.*, api_keys.name AS agent_name, p.slug AS project_slug, p.display_name AS project_display_name, ${SESSION_LABEL_SQL} AS display_label FROM sessions s LEFT JOIN api_keys ON api_keys.id = s.agent_id LEFT JOIN projects p ON p.id = s.project_id WHERE ${where} ORDER BY last_seen_at DESC`)
    .bind(...agentIds)
    .all<SessionRow & SessionProjectRow & { agent_name: string; display_label: string | null }>();
  return c.json({ sessions: rows.results.map(({ display_label, ...row }) => mapSessionProject({ ...row, label: display_label })) });
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
    .prepare(`UPDATE sessions SET ${sets.join(', ')} WHERE id = ? AND agent_id = ? AND project_id IS NOT NULL`)
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
