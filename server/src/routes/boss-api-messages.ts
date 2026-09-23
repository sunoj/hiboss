// Boss message reads and actions extracted without changing their HTTP contracts.
// Exports bossMessagesRouter; depends on authentication, D1, and shared boss access.
import { Hono, type Context } from 'hono';
import type { Env, MessageRow } from '../types';
import { getBossId, getBossRole } from '../middleware/auth';
import { getAccessibleAgentIds } from './boss-api-access';
import { mapMessageRow, clampNumber, parsePriorityFilter } from './message-helpers';
import { escapeLike } from './bosses';
import { forwardMessage, validateForwardChannel } from './message-forward';
import { notifyAgentCallback } from '../notify';
import { logAudit } from '../audit';
import { decodeRequiredInputCursor, fetchRequiredInputPage } from './boss-required-inputs';
const routes = new Hono<{ Bindings: Env }>();
const MAX_LIMIT = 100;

/** GET /api/boss/pending-inputs — complete required inputs, paged independently of history. */
routes.get('/pending-inputs', async (c) => {
  const bossId = getBossId(c);
  const agentIds = await getAccessibleAgentIds(c.env, bossId, getBossRole(c));
  let cursor: ReturnType<typeof decodeRequiredInputCursor>;
  try {
    cursor = decodeRequiredInputCursor(c.req.query('cursor'));
  } catch {
    return c.text('invalid pending-input cursor', 400);
  }
  return c.json(await fetchRequiredInputPage(c.env, agentIds, cursor, new Date().toISOString()));
});

function messageQuery(c: Context<{ Bindings: Env }>, agentIds: string[]): { limit: number; offset: number; clauses: string[]; binds: (string | number)[] } | null {
  const limit = clampNumber(c.req.query('limit'), 20, MAX_LIMIT);
  const offset = Math.max(Number(c.req.query('offset') ?? '0'), 0);
  const unread = c.req.query('unread') === 'true';
  const priorityFilter = parsePriorityFilter(c.req.query('priority'));
  const agentFilter = c.req.query('agent');
  const sessionFilter = c.req.query('session');
  const searchFilter = c.req.query('search');

  const clauses: string[] = [];
  const binds: (string | number)[] = [];
  if (agentFilter) {
    const match = agentIds.find((id) => id === agentFilter || id.startsWith(agentFilter));
    if (!match) return null;
    clauses.push('agent_id = ?');
    binds.push(match);
  } else {
    clauses.push(`agent_id IN (${agentIds.map(() => '?').join(', ')})`);
    binds.push(...agentIds);
  }

  const directionFilter = c.req.query('direction');
  if (directionFilter === 'all') {
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

  return { limit, offset, clauses, binds };
}

/** GET /api/boss/messages — list messages from accessible agents */
routes.get('/messages', async (c) => {
  const bossId = getBossId(c);
  const agentIds = await getAccessibleAgentIds(c.env, bossId, getBossRole(c));
  if (agentIds.length === 0) return c.json({ messages: [], total: 0 });

  const query = messageQuery(c, agentIds);
  if (!query) return c.json({ messages: [], total: 0 });
  const { limit, offset, clauses, binds } = query;

  const where = clauses.join(' AND ');
  const rows = await c.env.DB
    .prepare(`SELECT messages.*, api_keys.name AS agent_name, sessions.label AS session_label, sessions.branch AS session_branch, sessions.status AS session_status FROM (SELECT * FROM messages WHERE ${where}) messages LEFT JOIN api_keys ON api_keys.id = messages.agent_id LEFT JOIN sessions ON sessions.id = messages.session_id ORDER BY messages.created_at DESC LIMIT ? OFFSET ?`)
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
    .prepare("SELECT messages.*, api_keys.name AS agent_name FROM messages LEFT JOIN api_keys ON api_keys.id = messages.agent_id WHERE messages.id = ? OR messages.id LIKE ? ESCAPE '\\'")
    .bind(messageId, `${escapeLike(messageId)}%`)
    .first<MessageRow>();
  if (!row || !agentIds.includes(row.agent_id)) return c.text('not found', 404);
  const replies = await c.env.DB
    .prepare('SELECT messages.*, api_keys.name AS agent_name FROM messages LEFT JOIN api_keys ON api_keys.id = messages.agent_id WHERE reply_to = ? ORDER BY messages.created_at ASC')
    .bind(row.id)
    .all<MessageRow>();
  return c.json({ ...mapMessageRow(row), replies: (replies.results ?? []).map(mapMessageRow) });
});

routes.post('/messages/:id/forward', async (c) => {
  const bossId = getBossId(c);
  const role = getBossRole(c);
  if (role === 'viewer') return c.text('viewer cannot send messages', 403);
  const agentIds = await getAccessibleAgentIds(c.env, bossId, role);
  const messageId = c.req.param('id');
  const original = await c.env.DB
    .prepare("SELECT messages.*, api_keys.name AS agent_name FROM messages LEFT JOIN api_keys ON api_keys.id = messages.agent_id WHERE messages.id = ? OR messages.id LIKE ? ESCAPE '\\'")
    .bind(messageId, `${escapeLike(messageId)}%`)
    .first<MessageRow>();
  if (!original || !agentIds.includes(original.agent_id)) return c.text('not found', 404);
  const payload = await c.req.json<Record<string, unknown>>();
  const targetChannel = validateForwardChannel(payload.channel);
  if (!targetChannel) return c.text('channel must be discord or telegram', 400);
  try {
    const forwarded = await forwardMessage(c.env, original, targetChannel);
    c.executionCtx.waitUntil(logAudit(c.env, 'boss', bossId, 'message.forward', 'message', original.id, targetChannel));
    return c.json(mapMessageRow(forwarded), 201);
  } catch (error) {
    const message = error instanceof Error ? error.message : 'forward failed';
    const status = message === 'no channel configured' ? 400 : message === 'cannot forward boss messages' ? 403 : 502;
    return c.text(message, status);
  }
});

/** PATCH /api/boss/messages/:id — boss marks a message as read */
routes.patch('/messages/:id', async (c) => {
  const bossId = getBossId(c);
  const agentIds = await getAccessibleAgentIds(c.env, bossId, getBossRole(c));
  const messageId = c.req.param('id');
  const payload = await c.req.json<Record<string, unknown>>();
  const status = typeof payload.status === 'string' ? payload.status.trim() : '';
  if (!['read', 'delivered'].includes(status)) return c.text('status must be read or delivered', 400);
  const row = await c.env.DB
    .prepare("SELECT * FROM messages WHERE id = ? OR id LIKE ? ESCAPE '\\'")
    .bind(messageId, `${escapeLike(messageId)}%`)
    .first<MessageRow>();
  if (!row || !agentIds.includes(row.agent_id)) return c.text('not found', 404);
  const updated = await c.env.DB
    .prepare("UPDATE messages SET status = ?, updated_at = datetime('now') WHERE id = ? RETURNING *")
    .bind(status, row.id)
    .first<MessageRow>();
  if (!updated) return c.text('update failed', 500);
  return c.json(mapMessageRow(updated));
});

/** POST /api/boss/messages/:id/react — boss reacts to a message with emoji */
routes.post('/messages/:id/react', async (c) => {
  const bossId = getBossId(c);
  const role = getBossRole(c);
  if (role === 'viewer') return c.text('viewer cannot react', 403);
  const agentIds = await getAccessibleAgentIds(c.env, bossId, role);
  const messageId = c.req.param('id');
  const row = await c.env.DB
    .prepare("SELECT * FROM messages WHERE id = ? OR id LIKE ? ESCAPE '\\'")
    .bind(messageId, `${escapeLike(messageId)}%`)
    .first<MessageRow>();
  if (!row || !agentIds.includes(row.agent_id)) return c.text('not found', 404);
  const payload = await c.req.json<Record<string, unknown>>();
  const emoji = typeof payload.emoji === 'string' ? payload.emoji.trim() : '';
  if (!emoji) return c.text('emoji is required', 400);
  // Store reaction in message metadata
  const meta: Record<string, unknown> = row.metadata ? JSON.parse(row.metadata) : {};
  const reactions = Array.isArray(meta['reactions']) ? meta['reactions'] as { emoji: string; boss_id: string }[] : [];
  reactions.push({ emoji, boss_id: bossId });
  meta['reactions'] = reactions;
  await c.env.DB
    .prepare("UPDATE messages SET metadata = ?, updated_at = datetime('now') WHERE id = ?")
    .bind(JSON.stringify(meta), row.id)
    .run();
  c.executionCtx.waitUntil(logAudit(c.env, 'boss', bossId, 'message.react', 'message', row.id, emoji));
  // Notify agent via callback
  const replyRow: MessageRow = { ...row, body: emoji, direction: 'boss_to_agent', status: 'sent' };
  c.executionCtx.waitUntil(notifyAgentCallback(c.env, row.agent_id, replyRow));
  return c.json({ ok: true, emoji, message_id: row.id });
});

export const bossMessagesRouter = routes;
