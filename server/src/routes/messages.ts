// Router that implements agent-facing messaging endpoints atop the D1 schema.
// Exports POST/GET/PATCH/poll handlers for /api/messages and mounts helpers.
// Depends on Hono, the auth middleware, channel adapters, and shared types.

import { Hono } from 'hono';
import type { Channel, Direction, Env, MessageRow, Mode, Priority, Status } from '../types';
import { apiAuth, getAgentId } from '../middleware/auth';
import { setTelegramReaction } from '../channels/telegram';
import { notifyBossAgents } from '../notify';
import {
  buildFilters,
  buildInlineKeyboard,
  checkRateLimit,
  clampNumber,
  cleanupInlineKeyboard,
  deliverReply,
  deliverToChannelWithOptions,
  delay,
  deliverWithRetry,
  extractTelegramMessageId,
  fetchAgentName,
  fetchAllChannelConfigs,
  findByIdempotencyKey,
  fetchMessageRow,
  fetchMessageWithReplies,
  mapMessageRow,
  normalizeMetadata,
  parseOptions,
  parsePriorityFilter,
  priorityOptions,
  requireTelegramConfig,
  resolveChannelRouting,
  selectChannelConfig,
  validateChannel,
  validateOption,
} from './message-helpers';

const MAX_LIMIT = 100;
const DEFAULT_TIMEOUT_SECONDS = 300;
const WAIT_INTERVAL_MS = 1000;
const routes = new Hono<{ Bindings: Env }>({});
routes.use('*', apiAuth);

const modeOptions: Mode[] = ['async', 'blocking'];

routes.post('/', async (c) => {
  const agentId = getAgentId(c);
  const payload = await c.req.json<Record<string, unknown>>();
  const body = typeof payload.body === 'string' ? payload.body.trim() : '';
  if (!body) {
    return c.text('body is required', 400);
  }
  const idempotencyKey = typeof payload.idempotency_key === 'string' ? payload.idempotency_key.trim() || null : null;
  const agentConfig = await c.env.DB
    .prepare('SELECT default_priority, rate_limit, channel_routing, avatar_url FROM api_keys WHERE id = ?')
    .bind(agentId)
    .first<{ default_priority: string; rate_limit: number | null; channel_routing: string | null; avatar_url: string | null }>();
  const defaultPriority = (agentConfig?.default_priority ?? 'normal') as Priority;
  if (agentConfig?.rate_limit && await checkRateLimit(c.env, agentId, agentConfig.rate_limit)) {
    return c.text('rate limit exceeded', 429);
  }
  const mode = validateOption<Mode>(payload.mode, modeOptions, 'async');
  const priority = validateOption<Priority>(payload.priority, priorityOptions, defaultPriority);
  const explicitChannel = validateChannel(payload.channel);
  const routedChannel = !explicitChannel && agentConfig?.channel_routing
    ? resolveChannelRouting(agentConfig.channel_routing, priority as string)
    : undefined;
  const requestedChannel = explicitChannel ?? routedChannel;
  const fileUrl = typeof payload.file_url === 'string' ? payload.file_url.trim() : undefined;
  const messageType = typeof payload.type === 'string' ? payload.type.trim() : 'text';
  const sessionId = typeof payload.session_id === 'string' ? payload.session_id.trim() || null : null;
  const rawMetadata = normalizeMetadata(payload.metadata) ?? {};
  if (fileUrl) (rawMetadata as Record<string, unknown>)['file_url'] = fileUrl;
  const metadata = Object.keys(rawMetadata as Record<string, unknown>).length > 0 ? rawMetadata : null;
  const isUrgent = priority === 'critical' || priority === 'high';
  let channelConfigs: { channel: Channel; config: Record<string, unknown> }[] = [];
  try {
    if (isUrgent) {
      channelConfigs = await fetchAllChannelConfigs(c.env, agentId);
      if (requestedChannel) {
        // Put requested channel first, keep others
        channelConfigs.sort((a, b) => (a.channel === requestedChannel ? -1 : b.channel === requestedChannel ? 1 : 0));
      }
    } else {
      const single = await selectChannelConfig(c.env, agentId, requestedChannel);
      channelConfigs = [single];
    }
  } catch {
    // No channel configured — message will be stored without delivery.
  }
  const channel = channelConfigs[0]?.channel ?? requestedChannel ?? null;
  const metadataJson = metadata ? JSON.stringify(metadata) : null;
  if (idempotencyKey) {
    const existing = await findByIdempotencyKey(c.env, agentId, idempotencyKey);
    if (existing) {
      return c.json({ id: existing.id, status: existing.status, created_at: existing.created_at }, 200);
    }
  }
  const inserted = await c.env.DB
    .prepare(
      'INSERT INTO messages (agent_id, direction, mode, channel, body, status, priority, type, idempotency_key, metadata, session_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING *'
    )
    .bind(agentId, 'agent_to_boss', mode, channel, body, 'sent', priority, messageType, idempotencyKey, metadataJson, sessionId)
    .first<MessageRow>();
  if (!inserted) {
    return c.text('failed to persist', 500);
  }
  const options = parseOptions(payload.options);
  if (channelConfigs.length > 0) {
    const agentName = await fetchAgentName(c.env, agentId);
    const name = agentName ?? 'agent';
    const inlineKeyboard = options ? buildInlineKeyboard(inserted.id, options) : undefined;
    try {
      const results = await Promise.allSettled(
        channelConfigs.map((cc) =>
          deliverWithRetry(() => deliverToChannelWithOptions(cc.channel, cc.config, name, body, inlineKeyboard, fileUrl, agentConfig?.avatar_url ?? undefined))
        )
      );
      const deliveryResults = results.map((r, i) => ({
        channel: channelConfigs[i].channel,
        ok: r.status === 'fulfilled' && r.value.delivered,
        telegramMessageId: r.status === 'fulfilled' && r.value.delivered ? r.value.telegramMessageId : undefined,
      }));
      const anyDelivered = deliveryResults.some((d) => d.ok);
      if (anyDelivered) {
        const updates: string[] = ["status = 'delivered'", "updated_at = datetime('now')"];
        const binds: (string | number)[] = [];
        const meta = metadata ? { ...(metadata as Record<string, unknown>) } : {};
        const tgResult = deliveryResults.find((d) => d.telegramMessageId);
        if (tgResult?.telegramMessageId) {
          meta['telegram_message_id'] = tgResult.telegramMessageId;
        }
        if (isUrgent && channelConfigs.length > 1) {
          meta['delivery_results'] = deliveryResults.map((d) => ({ channel: d.channel, ok: d.ok }));
        }
        if (Object.keys(meta).length > 0) {
          updates.push('metadata = ?');
          binds.push(JSON.stringify(meta));
        }
        binds.push(inserted.id);
        await c.env.DB
          .prepare(`UPDATE messages SET ${updates.join(', ')} WHERE id = ?`)
          .bind(...binds)
          .run();
      } else if (!isUrgent) {
        const firstError = results.find((r) => r.status === 'rejected');
        const msg = firstError?.status === 'rejected' && firstError.reason instanceof Error ? firstError.reason.message : 'delivery failure';
        return c.json({ error: msg, id: inserted.id, status: inserted.status }, 502);
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : 'delivery failure';
      return c.json({ error: message, id: inserted.id, status: inserted.status }, 502);
    }
  }
  // Notify boss-agents for API channel messages (agent-as-boss)
  if (channel === 'api') {
    c.executionCtx.waitUntil(notifyBossAgents(c.env, agentId, inserted));
  }
  return c.json({ id: inserted.id, status: inserted.status, created_at: inserted.created_at }, 201);
});

routes.get('/', async (c) => {
  const agentId = getAgentId(c);
  const unread = c.req.query('unread');
  const directionParam = unread === 'true' ? 'boss_to_agent' : c.req.query('direction');
  const statusParam = unread === 'true' ? 'sent' : c.req.query('status');
  const direction = validateOption<Direction>(directionParam, ['agent_to_boss', 'boss_to_agent']);
  const status = validateOption<Status>(statusParam, ['sent', 'delivered', 'read', 'replied']);
  const priorityFilter = parsePriorityFilter(c.req.query('priority'));
  const typeFilter = c.req.query('type') || undefined;
  const sessionFilter = c.req.query('session') || undefined;
  const limit = clampNumber(c.req.query('limit'), 20, MAX_LIMIT);
  const offset = Math.max(Number(c.req.query('offset') ?? '0'), 0);
  const { where, binds } = buildFilters(agentId, direction, status, priorityFilter, typeFilter, sessionFilter);
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

routes.get('/:id', async (c) => {
  const agentId = getAgentId(c);
  const message = await fetchMessageWithReplies(c.env, agentId, c.req.param('id'));
  if (!message) {
    return c.text('not found', 404);
  }
  return c.json(message);
});

routes.post('/:id/reply', async (c) => {
  const agentId = getAgentId(c);
  const parent = await fetchMessageRow(c.env, agentId, c.req.param('id'));
  if (!parent) {
    return c.text('not found', 404);
  }
  const payload = await c.req.json<Record<string, unknown>>();
  const body = typeof payload.body === 'string' ? payload.body.trim() : '';
  if (!body) {
    return c.text('body is required', 400);
  }
  const replyDirection: Direction = parent.direction === 'boss_to_agent' ? 'agent_to_boss' : 'boss_to_agent';
  const inserted = await c.env.DB
    .prepare(
      'INSERT INTO messages (agent_id, direction, mode, channel, body, status, priority, reply_to) VALUES (?, ?, ?, ?, ?, ?, ?, ?) RETURNING *'
    )
    .bind(agentId, replyDirection, 'async', parent.channel, body, 'sent', 'normal', parent.id)
    .first<MessageRow>();
  if (!inserted) {
    return c.text('failed to persist', 500);
  }
  if (replyDirection === 'agent_to_boss' && parent.channel) {
    try {
      const channelConfig = await selectChannelConfig(c.env, agentId, parent.channel as Channel);
      const agentRow = await c.env.DB.prepare('SELECT name, avatar_url FROM api_keys WHERE id = ?').bind(agentId).first<{ name: string; avatar_url: string | null }>();
      const name = agentRow?.name ?? 'agent';
      const telegramReplyId = extractTelegramMessageId(parent.metadata);
      const result = await deliverWithRetry(() =>
        deliverReply(channelConfig.channel, channelConfig.config, name, body, telegramReplyId, agentRow?.avatar_url ?? undefined)
      );
      if (result.delivered) {
        const updates: string[] = ["status = 'delivered'", "updated_at = datetime('now')"];
        const binds: (string | number)[] = [];
        if (result.telegramMessageId) {
          updates.push('metadata = ?');
          binds.push(JSON.stringify({ telegram_message_id: result.telegramMessageId }));
        }
        binds.push(inserted.id);
        await c.env.DB
          .prepare(`UPDATE messages SET ${updates.join(', ')} WHERE id = ?`)
          .bind(...binds)
          .run();
      }
    } catch {
      // Channel delivery failed — message is still stored.
    }
  }
  await c.env.DB
    .prepare("UPDATE messages SET status = 'replied', updated_at = datetime('now') WHERE id = ?")
    .bind(parent.id)
    .run();
  return c.json(mapMessageRow(inserted), 201);
});

routes.patch('/:id', async (c) => {
  const agentId = getAgentId(c);
  const payload = await c.req.json<Record<string, unknown>>();
  const status = validateOption<Status>(payload.status, ['sent', 'delivered', 'read', 'replied']);
  if (!status) {
    return c.text('status is required', 400);
  }
  const updated = await c.env.DB
    .prepare(
      'UPDATE messages SET status = ?, updated_at = datetime(\'now\') WHERE id = ? AND agent_id = ? RETURNING *'
    )
    .bind(status, c.req.param('id'), agentId)
    .first<MessageRow>();
  if (!updated) {
    return c.text('not found', 404);
  }
  return c.json(mapMessageRow(updated));
});

routes.post('/:id/react', async (c) => {
  const agentId = getAgentId(c);
  const message = await fetchMessageRow(c.env, agentId, c.req.param('id'));
  if (!message) {
    return c.text('not found', 404);
  }
  const payload = await c.req.json<Record<string, unknown>>();
  const emoji = typeof payload.emoji === 'string' ? payload.emoji.trim() : '';
  if (!emoji) {
    return c.text('emoji is required', 400);
  }
  if (message.channel !== 'telegram') {
    return c.text('reactions only supported on telegram', 400);
  }
  const telegramMsgId = extractTelegramMessageId(message.metadata);
  if (!telegramMsgId) {
    return c.text('no telegram message id found', 400);
  }
  const channelConfig = await selectChannelConfig(c.env, agentId, 'telegram');
  const tgConfig = requireTelegramConfig(channelConfig.config);
  await setTelegramReaction(tgConfig.bot_token, tgConfig.chat_id, telegramMsgId, emoji);
  return c.json({ ok: true });
});

routes.post('/:id/poll', async (c) => {
  const agentId = getAgentId(c);
  const message = await fetchMessageRow(c.env, agentId, c.req.param('id'));
  if (!message) {
    return c.text('not found', 404);
  }
  if (message.mode !== 'blocking') {
    return c.text('not blocking message', 400);
  }
  const timeoutSec = clampNumber(c.req.query('timeout'), DEFAULT_TIMEOUT_SECONDS, DEFAULT_TIMEOUT_SECONDS);
  const deadline = Date.now() + timeoutSec * 1000;
  while (true) {
    const current = await fetchMessageWithReplies(c.env, agentId, message.id);
    if (current && (current.replies?.length ?? 0) > 0) {
      return c.json(current);
    }
    if (Date.now() >= deadline) {
      c.executionCtx.waitUntil(cleanupInlineKeyboard(c.env, agentId, message).catch(() => {}));
      const fallback = mapMessageRow(message);
      fallback.replies = [];
      return c.json(current ?? fallback);
    }
    await delay(Math.min(WAIT_INTERVAL_MS, deadline - Date.now()));
  }
});

export const messagesRouter = routes;
