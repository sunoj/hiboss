// Boss-authenticated API: lets bosses view agents, messages, sessions, and reply.
// Exports bossApiRouter mounted at /api/boss.
// Depends on Hono, boss auth middleware, and D1 bindings.

import { Hono } from 'hono';
import type { Env, MessageRow } from '../types';
import { bossAuth, getBossId, getBossRole, getBossName, hashApiKey } from '../middleware/auth';
import { mapMessageRow, clampNumber, parsePriorityFilter } from './message-helpers';
import { escapeLike } from './bosses';
import { notifyAgentCallback } from '../notify';
import { logAudit } from '../audit';
import { forwardMessage, validateForwardChannel } from './message-forward';
import { claimOptionReply } from './boss-option-reply';
import { streamBossOptions } from './boss-option-stream';
import { streamBossFeed } from './boss-feed-stream';
import { getBossOverview } from './boss-overview';
import { withdrawResolvedOptions } from './message-options';
import { validateBossPreferences } from './boss-preferences';

const MAX_LIMIT = 100;
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

/** GET /api/boss/overview — dashboard KPIs, priority distribution, session status, channel health */
routes.get('/overview', async (c) => {
  const bossId = getBossId(c);
  const agentIds = await getAccessibleAgentIds(c.env, bossId, getBossRole(c));
  return c.json(await getBossOverview(c.env, agentIds));
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
  const payload = await c.req.json<unknown>();
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
    return c.text('preferences must be an object', 400);
  }
  const preferences = payload as Record<string, unknown>;
  // Validate what the caller sent, not the merged result: bosses predating the typed
  // quiet-hours shape still hold the legacy { start, end } form, and validating the merge
  // would reject every write they make until that untouched key happens to be rewritten.
  const validation = validateBossPreferences(preferences);
  if (!validation.ok) return c.text(validation.error, 400);
  const existing = await c.env.DB.prepare('SELECT preferences FROM bosses WHERE id = ?').bind(bossId).first<{ preferences: string | null }>();
  if (!existing) return c.text('not found', 404);
  const current = safeParse(existing.preferences) ?? {};
  const merged = { ...current, ...preferences };
  await c.env.DB.prepare('UPDATE bosses SET preferences = ? WHERE id = ?').bind(JSON.stringify(merged), bossId).run();
  c.executionCtx.waitUntil(logAudit(c.env, 'boss', bossId, 'boss.preferences', 'boss', bossId, JSON.stringify(Object.keys(preferences))));
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

/** POST /api/boss/messages/:id/reply — boss replies to an agent message */
routes.post('/messages/:id/reply', async (c) => {
  const bossId = getBossId(c);
  const role = getBossRole(c);
  if (role === 'viewer') return c.text('viewer cannot send messages', 403);
  const agentIds = await getAccessibleAgentIds(c.env, bossId, role);
  const messageId = c.req.param('id');
  const parent = await c.env.DB
    .prepare("SELECT * FROM messages WHERE id = ? OR id LIKE ? ESCAPE '\\'")
    .bind(messageId, `${escapeLike(messageId)}%`)
    .first<MessageRow>();
  if (!parent || !agentIds.includes(parent.agent_id)) return c.text('not found', 404);
  const payload = await c.req.json<Record<string, unknown>>();
  const body = typeof payload.body === 'string' ? payload.body.trim() : '';
  if (!body) return c.text('body is required', 400);
  const optionClaim = await claimOptionReply(c.env, parent, body, true);
  if (optionClaim.kind === 'resolved') return c.text('option already resolved', 409);
  const bossName = getBossName(c);
  const metadata = JSON.stringify({ boss_id: bossId, boss_name: bossName });
  const inserted = await c.env.DB
    .prepare(
      'INSERT INTO messages (agent_id, direction, mode, channel, body, status, priority, reply_to, metadata) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING *'
    )
    .bind(parent.agent_id, 'boss_to_agent', 'async', 'api', body, 'sent', 'normal', parent.id, metadata)
    .first<MessageRow>();
  if (!inserted) return c.text('failed to persist', 500);
  if (optionClaim.kind === 'not_option') {
    await c.env.DB
      .prepare("UPDATE messages SET status = 'replied', updated_at = datetime('now') WHERE id = ?")
      .bind(parent.id)
      .run();
  }
  if (optionClaim.kind === 'claimed') {
    c.executionCtx.waitUntil(
      withdrawResolvedOptions(c.env, parent.agent_id, parent, body).catch(() => {}),
    );
  }
  c.executionCtx.waitUntil(notifyAgentCallback(c.env, parent.agent_id, inserted));
  c.executionCtx.waitUntil(logAudit(c.env, 'boss', bossId, 'message.reply', 'message', parent.id, bossName));
  return c.json(mapMessageRow(inserted), 201);
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
    .prepare('INSERT INTO api_keys (name, key_hash) VALUES (?, ?) RETURNING id, name')
    .bind(request.name, keyHash)
    .first<ApiKeyRow>();
  if (!inserted) return c.text('failed to persist', 500);
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

/** GET /api/boss/stream — SSE stream of new agent messages for the boss */
routes.get('/stream', async (c) => {
  const bossId = getBossId(c);
  const agentIds = await getAccessibleAgentIds(c.env, bossId, getBossRole(c));
  if (agentIds.length === 0) return c.text('no agents', 403);
  const { readable, writable } = new TransformStream();
  const writer = writable.getWriter();
  const encoder = new TextEncoder();

  const stream = c.req.query('options') === 'true'
    ? streamBossOptions(writer, encoder, c.env, agentIds)
    : c.req.query('feed') === 'true'
      ? streamBossFeed(writer, encoder, c.env, agentIds)
      : bossStreamLoop(writer, encoder, c.env, bossId, agentIds);
  c.executionCtx.waitUntil(stream);

  return new Response(readable, {
    headers: { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', 'Connection': 'keep-alive' },
  });
});

const BOSS_POLL_MS = 3000;
const BOSS_KEEPALIVE_MS = 15000;
const BOSS_MAX_DURATION_MS = 5 * 60 * 1000;

async function bossStreamLoop(
  writer: WritableStreamDefaultWriter, encoder: TextEncoder,
  env: Env, bossId: string, agentIds: string[],
): Promise<void> {
  const start = Date.now();
  let lastCheck = new Date().toISOString().replace('T', ' ').slice(0, 19);
  let lastKeepalive = Date.now();
  const seenIds = new Set<string>();
  const placeholders = agentIds.map(() => '?').join(', ');
  const sql = `SELECT messages.*, api_keys.name AS agent_name FROM messages LEFT JOIN api_keys ON api_keys.id = messages.agent_id WHERE agent_id IN (${placeholders}) AND direction = 'agent_to_boss' AND status = 'sent' AND messages.created_at >= ? ORDER BY messages.created_at ASC`;

  try {
    while (Date.now() - start < BOSS_MAX_DURATION_MS) {
      const rows = await env.DB.prepare(sql).bind(...agentIds, lastCheck).all<MessageRow>();
      for (const row of rows.results ?? []) {
        if (seenIds.has(row.id)) continue;
        const data = JSON.stringify(mapMessageRow(row));
        await writer.write(encoder.encode(`event: message\ndata: ${data}\n\n`));
        await env.DB.prepare("UPDATE messages SET status = 'delivered', updated_at = datetime('now') WHERE id = ?").bind(row.id).run();
        seenIds.add(row.id);
        lastCheck = row.created_at;
      }
      if (Date.now() - lastKeepalive >= BOSS_KEEPALIVE_MS) {
        await writer.write(encoder.encode(': keepalive\n\n'));
        lastKeepalive = Date.now();
      }
      await new Promise((r) => setTimeout(r, BOSS_POLL_MS));
    }
  } catch { /* client disconnected */ } finally {
    try { await writer.close(); } catch { /* already closed */ }
  }
}

function generateHex(bytes: number): string {
  const buf = new Uint8Array(bytes);
  crypto.getRandomValues(buf);
  return Array.from(buf).map((v) => v.toString(16).padStart(2, '0')).join('');
}

export const bossApiRouter = routes;
