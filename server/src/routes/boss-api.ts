// Boss-authenticated API: lets bosses view agents, messages, sessions, and reply.
// Exports bossApiRouter mounted at /api/boss.
// Depends on Hono, boss auth middleware, and D1 bindings.

import { Hono } from 'hono';
import type { Env, MessageRow } from '../types';
import { bossAuth, getBossId, getBossRole, getBossName } from '../middleware/auth';
import { mapMessageRow, clampNumber, parsePriorityFilter } from './message-helpers';
import { notifyAgentCallback } from '../notify';
import { logAudit } from '../audit';

const MAX_LIMIT = 100;

const routes = new Hono<{ Bindings: Env }>({});
routes.use('*', bossAuth);

/** Get all agent IDs this boss has access to. Admin = all agents. */
async function getAccessibleAgentIds(env: Env, bossId: string, role: string): Promise<string[]> {
  if (role === 'admin') {
    const rows = await env.DB.prepare('SELECT id FROM api_keys').all<{ id: string }>();
    return (rows.results ?? []).map((r) => r.id);
  }
  const rows = await env.DB
    .prepare('SELECT agent_id FROM boss_agent_access WHERE boss_id = ?')
    .bind(bossId)
    .all<{ agent_id: string }>();
  return (rows.results ?? []).map((r) => r.agent_id);
}

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
  return c.json({ ...boss, preferences: safeParse(boss.preferences as string | null), agent_ids: agentIds });
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
  const current = safeParse(existing.preferences) ?? {};
  const merged = { ...current, ...payload };
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
    .prepare(`SELECT id, name, role, last_used_at, created_at FROM api_keys WHERE id IN (${placeholders})`)
    .bind(...agentIds)
    .all();
  return c.json({ agents: rows.results ?? [] });
});

/** GET /api/boss/messages — list messages from accessible agents */
routes.get('/messages', async (c) => {
  const bossId = getBossId(c);
  const agentIds = await getAccessibleAgentIds(c.env, bossId, getBossRole(c));
  if (agentIds.length === 0) return c.json({ messages: [], total: 0 });

  const limit = clampNumber(c.req.query('limit'), 20, MAX_LIMIT);
  const offset = Math.max(Number(c.req.query('offset') ?? '0'), 0);
  const unread = c.req.query('unread') === 'true';
  const priorityFilter = parsePriorityFilter(c.req.query('priority'));
  const agentFilter = c.req.query('agent');
  const sessionFilter = c.req.query('session');
  const searchFilter = c.req.query('search');

  const clauses: string[] = [];
  const binds: (string | number)[] = [];

  // Filter by accessible agents (or specific agent)
  if (agentFilter) {
    const match = agentIds.find((id) => id === agentFilter || id.startsWith(agentFilter));
    if (!match) return c.json({ messages: [], total: 0 });
    clauses.push('agent_id = ?');
    binds.push(match);
  } else {
    clauses.push(`agent_id IN (${agentIds.map(() => '?').join(', ')})`);
    binds.push(...agentIds);
  }

  const directionFilter = c.req.query('direction');
  if (directionFilter === 'all') {
    // No direction filter — show all directions for session views
  } else {
    clauses.push("direction = 'agent_to_boss'");
  }
  if (unread) clauses.push("status IN ('sent', 'delivered')");
  if (sessionFilter) {
    clauses.push('session_id = ?');
    binds.push(sessionFilter);
  }
  if (priorityFilter && priorityFilter.length > 0) {
    clauses.push(`priority IN (${priorityFilter.map(() => '?').join(', ')})`);
    binds.push(...priorityFilter);
  }
  if (searchFilter) {
    clauses.push('body LIKE ?');
    binds.push(`%${searchFilter}%`);
  }

  const where = clauses.join(' AND ');
  const rows = await c.env.DB
    .prepare(`SELECT messages.*, api_keys.name AS agent_name FROM messages LEFT JOIN api_keys ON api_keys.id = messages.agent_id WHERE ${where} ORDER BY messages.created_at DESC LIMIT ? OFFSET ?`)
    .bind(...binds, limit, offset)
    .all<MessageRow>();
  const countRow = await c.env.DB
    .prepare(`SELECT COUNT(*) AS total FROM messages WHERE ${where}`)
    .bind(...binds)
    .first<{ total: number }>();
  return c.json({ messages: (rows.results ?? []).map(mapMessageRow), total: countRow?.total ?? 0 });
});

/** GET /api/boss/messages/:id — read a specific message with replies */
routes.get('/messages/:id', async (c) => {
  const bossId = getBossId(c);
  const agentIds = await getAccessibleAgentIds(c.env, bossId, getBossRole(c));
  const messageId = c.req.param('id');
  const row = await c.env.DB
    .prepare('SELECT messages.*, api_keys.name AS agent_name FROM messages LEFT JOIN api_keys ON api_keys.id = messages.agent_id WHERE messages.id = ? OR messages.id LIKE ?')
    .bind(messageId, `${messageId}%`)
    .first<MessageRow>();
  if (!row || !agentIds.includes(row.agent_id)) return c.text('not found', 404);
  const replies = await c.env.DB
    .prepare('SELECT messages.*, api_keys.name AS agent_name FROM messages LEFT JOIN api_keys ON api_keys.id = messages.agent_id WHERE reply_to = ? ORDER BY messages.created_at ASC')
    .bind(row.id)
    .all<MessageRow>();
  return c.json({ ...mapMessageRow(row), replies: (replies.results ?? []).map(mapMessageRow) });
});

/** POST /api/boss/messages/:id/reply — boss replies to an agent message */
routes.post('/messages/:id/reply', async (c) => {
  const bossId = getBossId(c);
  const role = getBossRole(c);
  if (role === 'viewer') return c.text('viewer cannot send messages', 403);
  const agentIds = await getAccessibleAgentIds(c.env, bossId, role);
  const messageId = c.req.param('id');
  const parent = await c.env.DB
    .prepare('SELECT * FROM messages WHERE id = ? OR id LIKE ?')
    .bind(messageId, `${messageId}%`)
    .first<MessageRow>();
  if (!parent || !agentIds.includes(parent.agent_id)) return c.text('not found', 404);
  const payload = await c.req.json<Record<string, unknown>>();
  const body = typeof payload.body === 'string' ? payload.body.trim() : '';
  if (!body) return c.text('body is required', 400);
  const bossName = getBossName(c);
  const metadata = JSON.stringify({ boss_id: bossId, boss_name: bossName });
  const inserted = await c.env.DB
    .prepare(
      'INSERT INTO messages (agent_id, direction, mode, channel, body, status, priority, reply_to, metadata) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING *'
    )
    .bind(parent.agent_id, 'boss_to_agent', 'async', 'api', body, 'sent', 'normal', parent.id, metadata)
    .first<MessageRow>();
  if (!inserted) return c.text('failed to persist', 500);
  await c.env.DB
    .prepare("UPDATE messages SET status = 'replied', updated_at = datetime('now') WHERE id = ?")
    .bind(parent.id)
    .run();
  c.executionCtx.waitUntil(notifyAgentCallback(c.env, parent.agent_id, inserted));
  c.executionCtx.waitUntil(logAudit(c.env, 'boss', bossId, 'message.reply', 'message', parent.id, bossName));
  return c.json(mapMessageRow(inserted), 201);
});

/** GET /api/boss/sessions — list sessions for accessible agents */
routes.get('/sessions', async (c) => {
  const bossId = getBossId(c);
  const agentIds = await getAccessibleAgentIds(c.env, bossId, getBossRole(c));
  if (agentIds.length === 0) return c.json({ sessions: [] });
  const placeholders = agentIds.map(() => '?').join(', ');
  const rows = await c.env.DB
    .prepare(`SELECT sessions.*, api_keys.name AS agent_name FROM sessions LEFT JOIN api_keys ON api_keys.id = sessions.agent_id WHERE sessions.agent_id IN (${placeholders}) AND sessions.last_seen_at > datetime('now', '-15 minutes') ORDER BY sessions.last_seen_at DESC`)
    .bind(...agentIds)
    .all();
  return c.json({ sessions: rows.results ?? [] });
});

export const bossApiRouter = routes;
