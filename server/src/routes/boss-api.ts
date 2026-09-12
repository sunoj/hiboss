// Boss-authenticated API: lets bosses view agents, messages, sessions, and reply.
// Exports bossApiRouter mounted at /api/boss.
// Depends on Hono, boss auth middleware, and D1 bindings.
import { SESSION_LABEL_SQL } from '../projects/session-label';
import { Hono } from 'hono';
import type { Env, MessageRow } from '../types';
import { bossAuth, getBossId, getBossRole, getBossName, getBossTokenId, hashApiKey } from '../middleware/auth';
import { mapMessageRow, validateOption, priorityOptions } from './message-helpers';
import { escapeLike } from './bosses';
import { notifyAgentCallback } from '../notify';
import { logAudit } from '../audit';
import { bossMessagesRouter } from './boss-api-messages';
import { bossStreamRouter } from './boss-api-stream';
import { validatePreferences } from './boss-preferences';
import { getAccessibleAgentIds } from './boss-api-access';
export { getAccessibleAgentIds } from './boss-api-access';
import { getBossOverview } from './boss-overview';
import { getBossHome } from './boss-home';
import { createMessageId, insertMessageWithEvent } from '../session-events';
import { bearerApiMetadata } from '../message-security';

interface JoinRequestRow {
  id: string;
  name: string;
  status: string;
  created_at: string;
  updated_at: string;
}
interface ApiKeyRow {
  id: string;
  name: string;
}
interface GroupRow {
  id: string;
  name: string;
  description: string | null;
  created_at: string;
}
interface RoutingRuleRow {
  id: string;
  owner_id: string;
  channel: string;
  pattern: string;
  target_agent_id: string;
  priority: number;
  enabled: number;
  created_at: string;
}
const routes = new Hono<{ Bindings: Env }>({});
routes.use('*', bossAuth);
routes.route('/', bossMessagesRouter);
routes.route('/', bossStreamRouter);

function safeParse(value: string | null | undefined): Record<string, unknown> | null {
  if (!value) return null;
  try { return JSON.parse(value) as Record<string, unknown>; } catch { return null; }
}

/** GET /api/boss/me — boss profile */
routes.get('/me', async (c) => {
  const bossId = getBossId(c);
  const boss = await c.env.DB
    .prepare('SELECT id, name, role, telegram_user_id, discord_user_id, agent_id, preferences, created_at FROM bosses WHERE id = ?')
    .bind(bossId)
    .first<Record<string, unknown>>();
  if (!boss) return c.text('not found', 404);
  const agentIds = await getAccessibleAgentIds(c.env, bossId, getBossRole(c));
  return c.json({ ...boss, token_id: getBossTokenId(c), preferences: safeParse(boss.preferences as string | null), agent_ids: agentIds });
});

/** GET /api/boss/overview — dashboard KPIs, priority distribution, session status, channel health */
routes.get('/overview', async (c) => {
  const bossId = getBossId(c);
  const agentIds = await getAccessibleAgentIds(c.env, bossId, getBossRole(c));
  return c.json(await getBossOverview(c.env, agentIds));
});

/** GET /api/boss/home — iOS Home tab aggregate (KPIs, activity, projects, attention) */
routes.get('/home', async (c) => {
  const bossId = getBossId(c);
  const agentIds = await getAccessibleAgentIds(c.env, bossId, getBossRole(c));
  return c.json(await getBossHome(c.env, getBossName(c), agentIds));
});

/** GET /api/boss/me/preferences — get boss preferences */
routes.get('/me/preferences', async (c) => {
  const bossId = getBossId(c);
  const row = await c.env.DB.prepare('SELECT preferences FROM bosses WHERE id = ?').bind(bossId).first<{ preferences: string | null }>();
  if (!row) return c.text('not found', 404);
  return c.json(safeParse(row.preferences) ?? {});
});

/** PUT /api/boss/me/preferences — update boss preferences (merge) */
routes.put('/me/preferences', async (c) => {
  const bossId = getBossId(c);
  const payload = await c.req.json<Record<string, unknown>>();
  const existing = await c.env.DB.prepare('SELECT preferences FROM bosses WHERE id = ?').bind(bossId).first<{ preferences: string | null }>();
  if (!existing) return c.text('not found', 404);
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return c.text('preferences must be an object', 400);
  const error = validatePreferences(payload);
  if (error) return c.text(error, 400);
  const current = safeParse(existing.preferences) ?? {};
  const { preferred_channel: _channel, notify_priorities: _priorities, ...retained } = current;
  const merged = { ...retained, ...payload };
  await c.env.DB.prepare('UPDATE bosses SET preferences = ? WHERE id = ?').bind(JSON.stringify(merged), bossId).run();
  c.executionCtx.waitUntil(logAudit(c.env, 'boss', bossId, 'boss.preferences', 'boss', bossId, JSON.stringify(Object.keys(payload))));
  return c.json(merged);
});

/** GET /api/boss/agents — list agents this boss can access */
routes.get('/agents', async (c) => {
  const bossId = getBossId(c);
  const agentIds = await getAccessibleAgentIds(c.env, bossId, getBossRole(c));
  if (agentIds.length === 0) return c.json({ agents: [] });
  const placeholders = agentIds.map(() => '?').join(', ');
  const rows = await c.env.DB
    .prepare(`SELECT a.id, a.name, a.role, a.last_used_at, a.created_at, (SELECT json_group_array(slug) FROM (SELECT DISTINCT p.slug FROM sessions s JOIN projects p ON p.id = s.project_id WHERE s.agent_id = a.id ORDER BY p.slug)) AS project_slugs FROM api_keys a WHERE a.id IN (${placeholders})`)
    .bind(...agentIds)
    .all<{ id: string; name: string; role: string | null; last_used_at: string | null; created_at: string; project_slugs: string }>();
  return c.json({ agents: rows.results.map(row => ({ ...row, project_slugs: JSON.parse(row.project_slugs) as string[] })) });
});

/** GET /api/boss/groups — list groups for accessible agents */
routes.get('/groups', async (c) => {
  const bossId = getBossId(c);
  const agentIds = await getAccessibleAgentIds(c.env, bossId, getBossRole(c));
  if (agentIds.length === 0) return c.json({ groups: [] });
  const placeholders = agentIds.map(() => '?').join(', ');
  const rows = await c.env.DB
    .prepare(
      `SELECT g.*, (SELECT COUNT(*) FROM agent_group_members m WHERE m.group_id = g.id) AS member_count FROM agent_groups g WHERE g.owner_id IN (${placeholders}) ORDER BY g.name`
    )
    .bind(...agentIds)
    .all<GroupRow & { member_count: number }>();
  return c.json({ groups: rows.results ?? [] });
});

/** GET /api/boss/routing-rules — list routing rules for accessible agents */
routes.get('/routing-rules', async (c) => {
  const bossId = getBossId(c);
  const agentIds = await getAccessibleAgentIds(c.env, bossId, getBossRole(c));
  if (agentIds.length === 0) return c.json({ rules: [] });
  const placeholders = agentIds.map(() => '?').join(', ');
  const rows = await c.env.DB
    .prepare(`SELECT * FROM routing_rules WHERE owner_id IN (${placeholders}) ORDER BY priority DESC`)
    .bind(...agentIds)
    .all<RoutingRuleRow>();
  return c.json({ rules: rows.results ?? [] });
});

/** GET /api/boss/audit — list audit log entries scoped to accessible agents */
routes.get('/audit', async (c) => {
  const bossId = getBossId(c);
  const role = getBossRole(c);
  const agentIds = await getAccessibleAgentIds(c.env, bossId, role);
  const params = c.req.query();
  const actorType = params.actor_type as string | undefined;
  const action = params.action as string | undefined;
  const limit = Math.min(parseInt(params.limit ?? '50', 10), 200);
  const offset = parseInt(params.offset ?? '0', 10);
  const clauses: string[] = [];
  const binds: (string | number)[] = [];

  if (role !== 'admin') {
    const agentScope = agentIds.length > 0
      ? `(actor_type = 'agent' AND actor_id IN (${agentIds.map(() => '?').join(', ')})) OR `
      : '';
    clauses.push(`(${agentScope}(actor_type = 'boss' AND actor_id = ?))`);
    binds.push(...agentIds, bossId);
  }
  if (actorType) {
    clauses.push('actor_type = ?');
    binds.push(actorType);
  }
  if (action) {
    clauses.push('action = ?');
    binds.push(action);
  }

  let sql = 'SELECT * FROM audit_log';
  if (clauses.length > 0) sql += ` WHERE ${clauses.join(' AND ')}`;
  const countSql = sql.replace('SELECT *', 'SELECT COUNT(*) as count');
  const countRow = await c.env.DB.prepare(countSql).bind(...binds).first<{ count: number }>();
  const total = countRow?.count ?? 0;

  sql += ' ORDER BY created_at DESC LIMIT ? OFFSET ?';
  binds.push(limit, offset);
  const rows = await c.env.DB.prepare(sql).bind(...binds).all();
  return c.json({ entries: rows.results ?? [], total });
});

/** GET /api/boss/sessions — list sessions for accessible agents */
routes.get('/sessions', async (c) => {
  const bossId = getBossId(c);
  const agentIds = await getAccessibleAgentIds(c.env, bossId, getBossRole(c));
  if (agentIds.length === 0) return c.json({ sessions: [] });
  const placeholders = agentIds.map(() => '?').join(', ');
  const rows = await c.env.DB
    .prepare(`SELECT s.*, api_keys.name AS agent_name, p.slug AS project_slug, ${SESSION_LABEL_SQL} AS label FROM sessions s LEFT JOIN projects p ON p.id = s.project_id LEFT JOIN api_keys ON api_keys.id = s.agent_id WHERE s.agent_id IN (${placeholders}) ${c.req.query('include_inactive') === 'true' ? '' : "AND s.last_seen_at > datetime('now', '-15 minutes')"} ORDER BY s.last_seen_at DESC`)
    .bind(...agentIds)
    .all();
  return c.json({ sessions: rows.results ?? [] });
});

/** POST /api/boss/sessions/:id/message — send a fresh command to a session's agent */
routes.post('/sessions/:id/message', async (c) => {
  const bossId = getBossId(c);
  const role = getBossRole(c);
  if (role === 'viewer') return c.text('viewer cannot send messages', 403);
  const agentIds = await getAccessibleAgentIds(c.env, bossId, role);
  const sessionId = c.req.param('id');
  const session = await c.env.DB
    .prepare("SELECT id, agent_id FROM sessions WHERE id = ? OR id LIKE ? ESCAPE '\\'")
    .bind(sessionId, `${escapeLike(sessionId)}%`)
    .first<{ id: string; agent_id: string }>();
  if (!session || !agentIds.includes(session.agent_id)) return c.text('not found', 404);

  const payload = await c.req.json<Record<string, unknown>>();
  const body = typeof payload.body === 'string' ? payload.body.trim() : '';
  if (!body) return c.text('body is required', 400);
  const priority = validateOption(payload.priority, priorityOptions, 'normal') ?? 'normal';
  const bossName = getBossName(c);
  const metadata = JSON.stringify(bearerApiMetadata(
    { id: bossId, name: bossName }, getBossTokenId(c),
  ));

  const inserted = await insertMessageWithEvent(
    c.env,
    "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, target_session_id, metadata) VALUES (?, ?, 'boss_to_agent', 'async', 'api', ?, 'sent', ?, ?, ?) RETURNING *",
    [createMessageId(), session.agent_id, body, priority, session.id, metadata],
    session.id,
  );
  if (!inserted) return c.text('failed to persist', 500);

  c.executionCtx.waitUntil(notifyAgentCallback(c.env, session.agent_id, inserted));
  c.executionCtx.waitUntil(logAudit(c.env, 'boss', bossId, 'session.message', 'session', session.id, bossName));
  return c.json(mapMessageRow(inserted), 201);
});

routes.get('/join-requests', async (c) => {
  if (getBossRole(c) !== 'admin') return c.text('admin access required', 403);
  const status = c.req.query('status');
  const sql = status
    ? 'SELECT id, name, status, created_at, updated_at FROM join_requests WHERE status = ? ORDER BY created_at DESC'
    : 'SELECT id, name, status, created_at, updated_at FROM join_requests ORDER BY created_at DESC';
  const query = c.env.DB.prepare(sql);
  const rows = status
    ? await query.bind(status).all<JoinRequestRow>()
    : await query.all<JoinRequestRow>();
  return c.json({ requests: rows.results ?? [] });
});

routes.post('/join-requests/:id/approve', async (c) => {
  if (getBossRole(c) !== 'admin') return c.text('admin access required', 403);
  const bossId = getBossId(c);
  const requestId = c.req.param('id');
  const request = await c.env.DB.prepare('SELECT * FROM join_requests WHERE id = ?').bind(requestId).first<JoinRequestRow>();
  if (!request) return c.text('not found', 404);
  if (request.status !== 'pending') return c.text('request already processed', 400);
  const key = `hb_${generateHex(16)}`;
  const keyHash = await hashApiKey(key);
  const inserted = await c.env.DB
    .prepare('INSERT INTO api_keys (name, key_hash) VALUES (?, ?) ON CONFLICT(name) DO NOTHING RETURNING id, name')
    .bind(request.name, keyHash)
    .first<ApiKeyRow>();
  if (!inserted) return c.text('agent name already exists', 409);
  await c.env.DB
    .prepare("UPDATE join_requests SET status = 'approved', api_key_id = ?, api_key = ?, updated_at = datetime('now') WHERE id = ?")
    .bind(inserted.id, key, request.id)
    .run();
  await c.env.DB
    .prepare('INSERT OR IGNORE INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
    .bind(bossId, inserted.id)
    .run();
  c.executionCtx.waitUntil(logAudit(c.env, 'boss', bossId, 'join.approve', 'join_request', request.id));
  return c.json({ id: request.id, name: request.name, status: 'approved', agent_id: inserted.id, key });
});

routes.post('/join-requests/:id/reject', async (c) => {
  if (getBossRole(c) !== 'admin') return c.text('admin access required', 403);
  const bossId = getBossId(c);
  const requestId = c.req.param('id');
  const request = await c.env.DB.prepare('SELECT * FROM join_requests WHERE id = ?').bind(requestId).first<JoinRequestRow>();
  if (!request) return c.text('not found', 404);
  if (request.status !== 'pending') return c.text('request already processed', 400);
  await c.env.DB
    .prepare("UPDATE join_requests SET status = 'rejected', updated_at = datetime('now') WHERE id = ?")
    .bind(request.id)
    .run();
  c.executionCtx.waitUntil(logAudit(c.env, 'boss', bossId, 'join.reject', 'join_request', request.id));
  return c.json({ id: request.id, name: request.name, status: 'rejected' });
});

function generateHex(bytes: number): string {
  const buf = new Uint8Array(bytes);
  crypto.getRandomValues(buf);
  return Array.from(buf).map((v) => v.toString(16).padStart(2, '0')).join('');
}

export const bossApiRouter = routes;
