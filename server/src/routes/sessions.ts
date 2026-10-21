// Router for session registration, discovery, and heartbeat.
// Exports sessionsRouter mounted at /api/sessions.
// Depends on Hono, auth middleware, and Env types.

import { parseProject, resolveProject, type Project } from '../projects';
import { SESSION_LABEL_SQL, mapSessionProject, type SessionProjectRow } from '../projects/session-label';
import { isRecord } from './progress-helpers';
import { Hono, type Context } from 'hono';
import type { Env, MessageRow } from '../types';
import { dualAuth, getAgentId, getBossId, getBossRole, isBossAuth } from '../middleware/auth';
import { getAccessibleAgentIds } from './boss-api';
import { announceSessionAsks, expireSessionAsks, sessionAsksExpiry } from '../abandoned-asks';
import { ADMITTED_PARENT_SQL, parseSessionIdentity, type SessionIdentity } from './session-identity';
import { parseSessionNickname, SESSION_NICKNAME_SQL } from './session-nickname';

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
  nickname: string | null;
  branch: string | null;
  cwd: string | null;
  status: SessionStatus;
  status_text: string | null;
  discord_thread_id: string | null;
  telegram_topic_id: number | null;
  host: string | null;
  runtime: string | null;
  dispatch_ref: string | null;
  parent_session_id: string | null;
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
  let label = typeof payload.label === 'string' ? payload.label.trim() || null
    : (cwd && branch ? `${cwd}/${branch}` : cwd ?? branch);
  const rawStatus = typeof payload.status === 'string' ? payload.status.trim() : '';
  const status: SessionStatus = SESSION_STATUSES.includes(rawStatus as SessionStatus)
    ? (rawStatus as SessionStatus) : 'working';
  const statusText = typeof payload.status_text === 'string' ? payload.status_text.trim() || null : null;
  const identity = parseSessionIdentity(payload);
  if (typeof identity === 'string') return c.text(identity, 400);
  const nickname = parseSessionNickname(payload.nickname);
  if (nickname instanceof Error) return c.text(nickname.message, 400);
  const project = await registrationProject(c, payload, id, agentId, cwd);
  if (project instanceof Response) return project;
  if (payload.project_identity !== undefined || payload.project !== undefined || !label) {
    label = branch ? `${project.slug}/${branch}`
      : (label?.includes('/') ? `${project.slug}/${label.split('/').slice(1).join('/')}` : project.slug);
  }
  const result = await upsertSession(c.env.DB, {
    id, agentId, label, branch, cwd, status, statusText, projectId: project.id, identity, nickname,
  });
  if (!result) {
    const existing = await c.env.DB.prepare('SELECT agent_id FROM sessions WHERE id = ?')
      .bind(id).first<{ agent_id: string }>();
    if (existing && existing.agent_id !== agentId) {
      return c.text('session belongs to another agent', 409);
    }
    return c.text('failed to persist session', 500);
  }
  // A completed session has no agent left to read an answer, whichever route completed it.
  if (status === 'completed') await expireSessionAsks(c.env, agentId, id);
  const parentRejected = identity.parentSessionId !== null
    && result.parent_session_id !== identity.parentSessionId;
  const details = await c.env.DB.prepare('SELECT display_name, avatar_url FROM projects WHERE id = ?')
    .bind(project.id).first<{ display_name: string; avatar_url: string | null }>();
  const body = mapSessionProject({ id, label, branch, cwd, status, status_text: statusText,
    nickname: result.nickname, project_id: project.id, project_slug: project.slug,
    project_display_name: details?.display_name ?? null, project_avatar_url: details?.avatar_url ?? null,
    host: identity.host, runtime: identity.runtime, dispatch_ref: identity.dispatchRef,
    parent_session_id: result.parent_session_id });
  return c.json(parentRejected ? { ...body, parent_rejected: true } : body, 201);
});

async function registrationProject(
  c: Context<{ Bindings: Env }>, payload: Record<string, unknown>,
  id: string, agentId: string, cwd: string | null,
): Promise<Project | Response> {
  const legacy = typeof payload.label === 'string' ? payload.label.split('/')[0]
    : cwd?.replace(/\/+$/, '').split('/').pop();
  const input = parseProject(payload.project_identity ?? payload.project ?? legacy);
  if (typeof input === 'string') return c.text(input, 400);
  const owner = await c.env.DB.prepare(`SELECT s.agent_id, p.id, p.slug FROM sessions s
    LEFT JOIN projects p ON p.id = s.project_id WHERE s.id = ?`).bind(id)
    .first<{ agent_id: string; id: Project['id'] | null; slug: string | null }>();
  if (owner && owner.agent_id !== agentId) return c.text('session belongs to another agent', 409);
  const resolved = input ? await resolveProject(c.env.DB, input, agentId,
    payload.project_identity || payload.project ? 'explicit' : 'label') : null;
  if (resolved && !resolved.ok) return c.text(resolved.error, 409);
  const project = resolved?.ok ? resolved.project
    : (owner?.id && owner.slug ? { id: owner.id, slug: owner.slug } : null);
  return project ?? c.text('project is required', 400);
}

interface SessionUpsert {
  id: string; agentId: string; label: string | null; branch: string | null; cwd: string | null;
  status: SessionStatus; statusText: string | null; projectId: string; identity: SessionIdentity;
  nickname: string | null;
}

interface SessionUpsertResult { id: string; parent_session_id: string | null; nickname: string | null }

// Inserts the session, or updates it when the caller already owns that id. A
// re-registration replaces the identity fields with what the caller sends now; the
// parent is admitted inside this one statement (see ADMITTED_PARENT_SQL).
function upsertSession(db: D1Database, s: SessionUpsert): Promise<SessionUpsertResult | null> {
  const { host, runtime, dispatchRef, parentSessionId } = s.identity;
  return db.prepare(
    `INSERT INTO sessions (id, agent_id, label, branch, cwd, status, status_text, project_id,
       nickname, host, runtime, dispatch_ref, parent_session_id)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ${SESSION_NICKNAME_SQL}, ?, ?, ?,
       ${parentSessionId === null ? 'NULL' : ADMITTED_PARENT_SQL})
     ON CONFLICT(id) DO UPDATE SET project_id = COALESCE(excluded.project_id, sessions.project_id),
       label = excluded.label, branch = excluded.branch, cwd = excluded.cwd, status = excluded.status,
       status_text = excluded.status_text, host = excluded.host, runtime = excluded.runtime,
       dispatch_ref = excluded.dispatch_ref, parent_session_id = excluded.parent_session_id,
       nickname = excluded.nickname, last_seen_at = datetime('now')
     WHERE sessions.agent_id = excluded.agent_id
     RETURNING id, parent_session_id, nickname`,
  ).bind(s.id, s.agentId, s.label, s.branch, s.cwd, s.status, s.statusText, s.projectId,
    s.id, s.nickname, s.projectId, host, runtime, dispatchRef,
    ...(parentSessionId === null ? [] : [s.agentId, parentSessionId, s.id, s.id]))
    .first<SessionUpsertResult>();
}

// GET /api/sessions — list active sessions (within STALE_MINUTES)
routes.get('/', async (c) => {
  // The legacy all parameter is accepted but never expands the caller's scope.
  const agentIds = isBossAuth(c)
    ? await getAccessibleAgentIds(c.env, getBossId(c), getBossRole(c))
    : [getAgentId(c)];
  if (agentIds.length === 0) return c.json({ sessions: [] });
  const placeholders = agentIds.map(() => '?').join(', ');
  const where = `s.agent_id IN (${placeholders})
    AND last_seen_at > datetime('now', '-${STALE_MINUTES} minutes')`;
  const rows = await c.env.DB
    .prepare(`SELECT s.*, api_keys.name AS agent_name, p.slug AS project_slug,
      p.display_name AS project_display_name, p.avatar_url AS project_avatar_url,
      ${SESSION_LABEL_SQL} AS display_label FROM sessions s
      LEFT JOIN api_keys ON api_keys.id = s.agent_id LEFT JOIN projects p ON p.id = s.project_id
      WHERE ${where} ORDER BY last_seen_at DESC`)
    .bind(...agentIds)
    .all<SessionRow & SessionProjectRow & { agent_name: string; display_label: string | null }>();
  return c.json({ sessions: rows.results.map(({ display_label, ...row }) =>
    mapSessionProject({ ...row, label: display_label })) });
});

// PATCH /api/sessions/:id — heartbeat with optional status update
routes.patch('/:id', async (c) => {
  if (isBossAuth(c)) return c.text('agent required', 403);
  const agentId = getAgentId(c);
  const contentType = c.req.header('content-type') || '';
  let status: SessionStatus | undefined;
  let statusText: string | null | undefined;
  let nickname: string | null = null;
  if (contentType.includes('application/json')) {
    const payload = await c.req.json<unknown>().catch(() => null);
    if (!isRecord(payload)) return c.text('session body must be an object', 400);
    const parsedNickname = parseSessionNickname(payload.nickname);
    if (parsedNickname instanceof Error) return c.text(parsedNickname.message, 400);
    nickname = parsedNickname;
    const rawStatus = typeof payload.status === 'string' ? payload.status.trim() : '';
    if (rawStatus && SESSION_STATUSES.includes(rawStatus as SessionStatus)) {
      status = rawStatus as SessionStatus;
    }
    if ('status_text' in payload) {
      statusText = typeof payload.status_text === 'string' ? payload.status_text.trim() || null : null;
    }
  }
  const sets = ["last_seen_at = datetime('now')", `nickname = ${SESSION_NICKNAME_SQL}`];
  const binds: (string | null)[] = [c.req.param('id'), nickname, null];
  if (status) {
    sets.push('status = ?');
    binds.push(status);
  }
  if (statusText !== undefined) {
    sets.push('status_text = ?');
    binds.push(statusText);
  }
  binds.push(c.req.param('id'), agentId);
  const result = await c.env.DB
    .prepare(`UPDATE sessions SET ${sets.join(', ')}
      WHERE id = ? AND agent_id = ? AND project_id IS NOT NULL RETURNING nickname`)
    .bind(...binds)
    .first<{ nickname: string | null }>();
  if (!result) return c.text('not found', 404);
  // A completed session has no agent left to read an answer.
  if (status === 'completed') await expireSessionAsks(c.env, agentId, c.req.param('id'));
  return c.json({ ok: true, nickname: result.nickname });
});

// DELETE /api/sessions/:id — deregister. One batch, so a failure leaves the session and its
// asks untouched. A session that panels reference stays as a completed row: the panels keep
// their history and session label, and their lifecycle stays with the panel lease.
routes.delete('/:id', async (c) => {
  if (isBossAuth(c)) return c.text('agent required', 403);
  const agentId = getAgentId(c);
  const sessionId = c.req.param('id');
  const db = c.env.DB;
  const ownedSession = 'SELECT id FROM sessions WHERE id = ? AND agent_id = ?';
  const [expired] = await db.batch([
    sessionAsksExpiry(db, agentId, sessionId),
    db.prepare(`DELETE FROM session_events WHERE session_id IN (${ownedSession})`).bind(sessionId, agentId),
    db.prepare(`DELETE FROM destination_routes WHERE session_id IN (${ownedSession})`).bind(sessionId, agentId),
    db.prepare("UPDATE sessions SET telegram_topic_id = NULL, status = 'completed' WHERE id = ? AND agent_id = ?")
      .bind(sessionId, agentId),
    // A child must not keep pointing at an id that a later registration could claim.
    db.prepare(`UPDATE sessions SET parent_session_id = NULL
      WHERE parent_session_id IN (${ownedSession})`).bind(sessionId, agentId),
    db.prepare(`DELETE FROM sessions WHERE id = ? AND agent_id = ?
      AND NOT EXISTS (SELECT 1 FROM panels WHERE panels.session_id = sessions.id)`).bind(sessionId, agentId),
  ]);
  await announceSessionAsks(c.env, (expired.results ?? []) as MessageRow[]);
  return c.json({ ok: true });
});

export const sessionsRouter = routes;
