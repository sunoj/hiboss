// Boss-agent inbox: allows an agent acting as boss to read and reply to sub-agent messages.
// Exports bossInboxRouter mounted at /api/boss/inbox.
// Depends on Hono, auth middleware, D1, and notify helpers.

import { Hono } from 'hono';
import type { Env, MessageRow, Priority, Status } from '../types';
import { apiAuth, getAgentId } from '../middleware/auth';
import { mapMessageRow, parsePriorityFilter, priorityOptions, clampNumber, validateOption } from './message-helpers';
import { escapeLike } from './bosses';
import { notifyAgentCallback } from '../notify';

const MAX_LIMIT = 100;

interface BossRecord { id: string; name: string; role: string }

const routes = new Hono<{ Bindings: Env }>({});
routes.use('*', apiAuth);

/** Resolve the boss record for the current agent. */
async function findBossByAgentId(env: Env, agentId: string): Promise<BossRecord | null> {
  return env.DB
    .prepare('SELECT id, name, role FROM bosses WHERE agent_id = ?')
    .bind(agentId)
    .first<BossRecord>();
}

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

/** GET /api/boss/inbox — list messages from sub-agents. */
routes.get('/', async (c) => {
  const agentId = getAgentId(c);
  const boss = await findBossByAgentId(c.env, agentId);
  if (!boss) {
    return c.text('not a boss agent', 403);
  }
  const agentIds = await getAccessibleAgentIds(c.env, boss.id, boss.role);
  if (agentIds.length === 0) {
    return c.json({ messages: [], total: 0 });
  }
  const unread = c.req.query('unread') === 'true';
  const priorityFilter = parsePriorityFilter(c.req.query('priority'));
  const limit = clampNumber(c.req.query('limit'), 20, MAX_LIMIT);
  const offset = Math.max(Number(c.req.query('offset') ?? '0'), 0);
  const countOnly = c.req.query('count') === 'true';

  // Build WHERE clause: messages from sub-agents directed to boss
  const clauses: string[] = [];
  const binds: (string | number)[] = [];
  const placeholders = agentIds.map(() => '?').join(', ');
  clauses.push(`agent_id IN (${placeholders})`);
  binds.push(...agentIds);
  clauses.push("direction = 'agent_to_boss'");
  if (unread) {
    clauses.push("status IN ('sent', 'delivered')");
  }
  if (priorityFilter && priorityFilter.length > 0) {
    const pp = priorityFilter.map(() => '?').join(', ');
    clauses.push(`priority IN (${pp})`);
    binds.push(...priorityFilter);
  }
  const where = clauses.join(' AND ');

  if (countOnly) {
    const row = await c.env.DB
      .prepare(`SELECT COUNT(*) AS total FROM messages WHERE ${where}`)
      .bind(...binds)
      .first<{ total: number }>();
    return c.json({ total: row?.total ?? 0 });
  }

  const rows = await c.env.DB
    .prepare(
      `SELECT messages.*, api_keys.name AS agent_name FROM messages LEFT JOIN api_keys ON api_keys.id = messages.agent_id WHERE ${where} ORDER BY messages.created_at DESC LIMIT ? OFFSET ?`
    )
    .bind(...binds, limit, offset)
    .all<MessageRow>();
  const countRow = await c.env.DB
    .prepare(`SELECT COUNT(*) AS total FROM messages WHERE ${where}`)
    .bind(...binds)
    .first<{ total: number }>();
  return c.json({ messages: (rows.results ?? []).map(mapMessageRow), total: countRow?.total ?? 0 });
});

/** GET /api/boss/inbox/:id — read a specific sub-agent message with replies. */
routes.get('/:id', async (c) => {
  const agentId = getAgentId(c);
  const boss = await findBossByAgentId(c.env, agentId);
  if (!boss) {
    return c.text('not a boss agent', 403);
  }
  const messageId = c.req.param('id');
  const row = await c.env.DB
    .prepare("SELECT messages.*, api_keys.name AS agent_name FROM messages LEFT JOIN api_keys ON api_keys.id = messages.agent_id WHERE messages.id = ? OR messages.id LIKE ? ESCAPE '\\'")
    .bind(messageId, `${escapeLike(messageId)}%`)
    .first<MessageRow>();
  if (!row) {
    return c.text('not found', 404);
  }
  // Verify boss has access to this agent
  const agentIds = await getAccessibleAgentIds(c.env, boss.id, boss.role);
  if (!agentIds.includes(row.agent_id)) {
    return c.text('no access to this agent', 403);
  }
  // Fetch replies
  const replies = await c.env.DB
    .prepare('SELECT messages.*, api_keys.name AS agent_name FROM messages LEFT JOIN api_keys ON api_keys.id = messages.agent_id WHERE reply_to = ? ORDER BY messages.created_at ASC')
    .bind(row.id)
    .all<MessageRow>();
  return c.json({ ...mapMessageRow(row), replies: (replies.results ?? []).map(mapMessageRow) });
});

/** POST /api/boss/inbox/:id/reply — boss-agent replies to a sub-agent message. */
routes.post('/:id/reply', async (c) => {
  const agentId = getAgentId(c);
  const boss = await findBossByAgentId(c.env, agentId);
  if (!boss) {
    return c.text('not a boss agent', 403);
  }
  if (boss.role === 'viewer') {
    return c.text('viewer cannot send messages', 403);
  }
  const messageId = c.req.param('id');
  const parent = await c.env.DB
    .prepare("SELECT * FROM messages WHERE id = ? OR id LIKE ? ESCAPE '\\'")
    .bind(messageId, `${escapeLike(messageId)}%`)
    .first<MessageRow>();
  if (!parent) {
    return c.text('not found', 404);
  }
  const agentIds = await getAccessibleAgentIds(c.env, boss.id, boss.role);
  if (!agentIds.includes(parent.agent_id)) {
    return c.text('no access to this agent', 403);
  }
  const payload = await c.req.json<Record<string, unknown>>();
  const body = typeof payload.body === 'string' ? payload.body.trim() : '';
  if (!body) {
    return c.text('body is required', 400);
  }
  const metadata = JSON.stringify({ boss_id: boss.id, boss_name: boss.name });
  const inserted = await c.env.DB
    .prepare(
      'INSERT INTO messages (agent_id, direction, mode, channel, body, status, priority, reply_to, metadata) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING *'
    )
    .bind(parent.agent_id, 'boss_to_agent', 'async', 'api', body, 'sent', 'normal', parent.id, metadata)
    .first<MessageRow>();
  if (!inserted) {
    return c.text('failed to persist', 500);
  }
  // Mark parent as replied
  await c.env.DB
    .prepare("UPDATE messages SET status = 'replied', updated_at = datetime('now') WHERE id = ?")
    .bind(parent.id)
    .run();
  // Notify sub-agent via callback
  c.executionCtx.waitUntil(notifyAgentCallback(c.env, parent.agent_id, inserted));
  return c.json(mapMessageRow(inserted), 201);
});

/** PATCH /api/boss/inbox/:id — boss-agent marks a message as read. */
routes.patch('/:id', async (c) => {
  const agentId = getAgentId(c);
  const boss = await findBossByAgentId(c.env, agentId);
  if (!boss) {
    return c.text('not a boss agent', 403);
  }
  const messageId = c.req.param('id');
  const payload = await c.req.json<Record<string, unknown>>();
  const status = validateOption<Status>(payload.status, ['sent', 'delivered', 'read', 'replied']);
  if (!status) {
    return c.text('status is required', 400);
  }
  const existing = await c.env.DB
    .prepare('SELECT * FROM messages WHERE id = ?')
    .bind(messageId)
    .first<MessageRow>();
  if (!existing) {
    return c.text('not found', 404);
  }
  const agentIds = await getAccessibleAgentIds(c.env, boss.id, boss.role);
  if (!agentIds.includes(existing.agent_id)) {
    return c.text('no access to this agent', 403);
  }
  const updated = await c.env.DB
    .prepare("UPDATE messages SET status = ?, updated_at = datetime('now') WHERE id = ? RETURNING *")
    .bind(status, messageId)
    .first<MessageRow>();
  if (!updated) {
    return c.text('not found', 404);
  }
  return c.json(mapMessageRow(updated));
});

export const bossInboxRouter = routes;
