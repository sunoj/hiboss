// Router that implements agent-facing messaging endpoints atop the D1 schema.
// Exports POST/GET/PATCH/poll handlers for /api/messages, plus reactions sub-router.
// Depends on Hono, the auth middleware, channel adapters, and shared types.

import { Hono } from 'hono';
import type { Channel, Direction, Env, MessageRow, Mode, Priority, Status } from '../types';
import { apiAuth, getAgentId } from '../middleware/auth';
import { notifyBossAgents, notifyTargetAgent } from '../notify';
import { getDeliveryErrorMessage, persistDeliveryFailure } from './delivery';
import { deliverAgentMessage } from './agent-delivery';
import { getAgentQuietHoursEnd } from './quiet-hours';
import { reactionsRouter } from './reactions';
import {
  buildFilters,
  buildInlineKeyboard,
  checkRateLimit,
  clampNumber,
  expireMessageOptions,
  deliverReply,
  delay,
  deliverWithRetry,
  expirePreviousOptions,
  extractTelegramMessageId,
  fetchAllChannelConfigs,
  findByIdempotencyKey,
  fetchMessageRow,
  fetchMessageWithReplies,
  inferSessionStatus,
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
import { propagateMessageEdit } from './message-edit';
import { ensureTopicForSession } from './session-channels';
import { logAudit } from '../audit';
import { forwardMessage, validateForwardChannel } from './message-forward';

const MAX_LIMIT = 100;
const DEFAULT_TIMEOUT_SECONDS = 300;
const WAIT_INTERVAL_MS = 1000;
const VALID_TRANSITIONS: Record<string, string[]> = {
  sent: ['delivered', 'read', 'replied', 'expired'],
  delivered: ['read', 'replied', 'expired'],
  read: ['replied', 'expired'],
};
const routes = new Hono<{ Bindings: Env }>({});
routes.use('*', apiAuth);

const modeOptions: Mode[] = ['async', 'blocking'];

function isUniqueConstraintError(error: unknown): boolean {
  return error instanceof Error && error.message.includes('UNIQUE constraint failed');
}

function escapeLike(value: string): string {
  return value.replace(/[%_\\]/g, '\\$&');
}

async function enqueueDelivery(
  env: Env,
  messageId: string,
  agentId: string,
  channel: Channel,
  config: Record<string, unknown>,
  scheduledAt: Date,
): Promise<void> {
  await env.DB
    .prepare('INSERT INTO delivery_queue (message_id, agent_id, channel, config, scheduled_at) VALUES (?, ?, ?, ?, ?)')
    .bind(messageId, agentId, channel, JSON.stringify(config), scheduledAt.toISOString())
    .run();
}

export async function insertMessageWithRecovery(
  env: Env,
  agentId: string,
  values: [Direction, Mode, Channel | null, string, Priority, string, string | null, string | null, string | null, string | null, string | null]
): Promise<{ inserted: MessageRow | null; existing: MessageRow | null }> {
  const [direction, mode, channel, body, priority, messageType, idempotencyKey, metadataJson, sessionId, targetAgentId, targetSessionId] = values;
  try {
    const inserted = await env.DB
      .prepare(
        'INSERT INTO messages (agent_id, direction, mode, channel, body, status, priority, type, idempotency_key, metadata, session_id, target_agent_id, target_session_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING *'
      )
      .bind(agentId, direction, mode, channel, body, 'sent', priority, messageType, idempotencyKey, metadataJson, sessionId, targetAgentId, targetSessionId)
      .first<MessageRow>();
    return { inserted, existing: null };
  } catch (error) {
    if (!idempotencyKey || !isUniqueConstraintError(error)) throw error;
    const existing = await findByIdempotencyKey(env, agentId, idempotencyKey);
    if (existing) {
      return { inserted: null, existing };
    }
    throw error;
  }
}

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
  const mode = validateOption<Mode>(payload.mode, modeOptions, 'async') as Mode;
  const priority = validateOption<Priority>(payload.priority, priorityOptions, defaultPriority) as Priority;
  const explicitChannel = validateChannel(payload.channel);
  const routedChannel = !explicitChannel && agentConfig?.channel_routing
    ? resolveChannelRouting(agentConfig.channel_routing, priority as string)
    : undefined;
  const requestedChannel = explicitChannel ?? routedChannel;
  const fileUrl = typeof payload.file_url === 'string' ? payload.file_url.trim() : undefined;
  const messageType = typeof payload.type === 'string' ? payload.type.trim() : 'text';
  const sessionId = typeof payload.session_id === 'string' ? payload.session_id.trim() || null : null;
  const toAgent = typeof payload.to === 'string' ? payload.to.trim() || null : null;
  const options = parseOptions(payload.options);
  const rawMetadata = normalizeMetadata(payload.metadata) ?? {};
  if (fileUrl) (rawMetadata as Record<string, unknown>)['file_url'] = fileUrl;
  if (options) (rawMetadata as Record<string, unknown>)['options'] = options;
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
  // Resolve targeting: try agent name/id first, then session label/id
  let targetAgentId: string | null = null;
  let targetSessionId: string | null = null;
  let direction: Direction = 'agent_to_boss';
  let targetWarning: string | null = null;
  if (toAgent) {
    // 1. Try agent by name or id prefix
    const agentTarget = await c.env.DB
      .prepare("SELECT id FROM api_keys WHERE name = ? OR id LIKE ? ESCAPE '\\' LIMIT 1")
      .bind(toAgent, `${escapeLike(toAgent)}%`)
      .first<{ id: string }>();
    if (agentTarget) {
      targetAgentId = agentTarget.id;
      direction = 'agent_to_agent';
    } else {
      // 2. Try session by label or id prefix, prefer most recently active.
      // Exclude the sender's own session so a colliding label can never self-target
      // (all sessions of one agent share a key; the newest same-label session is often self).
      const excludeSelf = sessionId ? ' AND id != ?' : '';
      const sessionTarget = await c.env.DB
        .prepare(`SELECT id, agent_id, status, last_seen_at FROM sessions WHERE (label = ? OR id LIKE ? ESCAPE '\\')${excludeSelf} ORDER BY last_seen_at DESC LIMIT 1`)
        .bind(...(sessionId ? [toAgent, `${escapeLike(toAgent)}%`, sessionId] : [toAgent, `${escapeLike(toAgent)}%`]))
        .first<{ id: string; agent_id: string; status: string | null; last_seen_at: string | null }>();
      if (sessionTarget) {
        targetAgentId = sessionTarget.agent_id;
        targetSessionId = sessionTarget.id;
        direction = 'agent_to_agent';
        // Warn if target session is completed or stale (>15 min)
        if (sessionTarget.status === 'completed') {
          targetWarning = `target session '${toAgent}' is completed`;
        } else if (sessionTarget.last_seen_at) {
          const lastSeen = new Date(sessionTarget.last_seen_at + 'Z').getTime();
          if (Date.now() - lastSeen > 15 * 60 * 1000) {
            targetWarning = `target session '${toAgent}' last seen ${Math.round((Date.now() - lastSeen) / 60000)}m ago`;
          }
        }
      } else {
        return c.text(`target not found: ${toAgent}`, 404);
      }
    }
  }
  // Agent-to-agent messages use 'api' channel; others use resolved channel config
  const channel = direction === 'agent_to_agent' ? 'api' : (channelConfigs[0]?.channel ?? requestedChannel ?? null);
  const metadataJson = metadata ? JSON.stringify(metadata) : null;
  if (idempotencyKey) {
    const existing = await findByIdempotencyKey(c.env, agentId, idempotencyKey);
    if (existing) {
      return c.json({ id: existing.id, status: existing.status, created_at: existing.created_at }, 200);
    }
  }
  const { inserted, existing } = await insertMessageWithRecovery(c.env, agentId, [
    direction,
    mode,
    channel,
    body,
    priority,
    messageType,
    idempotencyKey,
    metadataJson,
    sessionId,
    targetAgentId,
    targetSessionId,
  ]);
  if (existing) {
    return c.json({ id: existing.id, status: existing.status, created_at: existing.created_at }, 200);
  }
  if (!inserted) {
    return c.text('failed to persist', 500);
  }
  // Set expires_at for messages with options (enables cron-based expiry sweep)
  if (options && inserted) {
    const timeoutSec = mode === 'blocking' && typeof payload.timeout === 'number'
      ? Math.max(60, Math.min(payload.timeout, 3600))
      : DEFAULT_TIMEOUT_SECONDS;
    const expiresAt = new Date(Date.now() + timeoutSec * 1000).toISOString();
    await c.env.DB.prepare('UPDATE messages SET expires_at = ? WHERE id = ?').bind(expiresAt, inserted.id).run();
  }
  // Auto-update session status based on message characteristics
  if (sessionId && direction === 'agent_to_boss') {
    c.executionCtx.waitUntil(inferSessionStatus(c.env, agentId, sessionId, mode, priority as string, body));
  }
  let queuedForQuietHours = false;
  if (channelConfigs.length > 0 && direction === 'agent_to_boss' && !isUrgent) {
    const quietHoursEnd = await getAgentQuietHoursEnd(c.env, agentId);
    if (quietHoursEnd) {
      await enqueueDelivery(c.env, inserted.id, agentId, channelConfigs[0].channel, channelConfigs[0].config, quietHoursEnd);
      queuedForQuietHours = true;
    }
  }
  if (channelConfigs.length > 0 && direction !== 'agent_to_agent' && !queuedForQuietHours) {
    const agentRow = await c.env.DB
      .prepare('SELECT name FROM api_keys WHERE id = ?')
      .bind(agentId)
      .first<{ name: string }>();
    const resolvedAgentName = agentRow?.name ?? 'agent';
    const inlineKeyboard = options ? buildInlineKeyboard(inserted.id, options) : undefined;
    try {
      const results = await Promise.allSettled(
        channelConfigs.map((cc) =>
          deliverAgentMessage(c.env, cc, {
            agentId,
            agentName: resolvedAgentName,
            body,
            sessionId,
            inlineKeyboard,
            fileUrl,
            avatarUrl: agentConfig?.avatar_url ?? undefined,
          })
        )
      );
      const deliveryResults = results.map((r, i) => ({
        channel: channelConfigs[i].channel,
        ok: r.status === 'fulfilled' && r.value.delivered,
        telegramMessageId: r.status === 'fulfilled' && r.value.delivered ? r.value.telegramMessageId : undefined,
        discordMessageId: r.status === 'fulfilled' && r.value.delivered ? r.value.discordMessageId : undefined,
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
        const dcResult = deliveryResults.find((d) => d.discordMessageId);
        if (dcResult?.discordMessageId) {
          meta['discord_message_id'] = dcResult.discordMessageId;
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
      } else {
        const firstError = results.find((r) => r.status === 'rejected');
        const message = firstError?.status === 'rejected'
          ? getDeliveryErrorMessage(firstError.reason)
          : 'delivery failure';
        await persistDeliveryFailure(c.env, inserted.id, message);
        return c.json({ error: message, id: inserted.id, status: inserted.status }, 502);
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : 'delivery failure';
      await persistDeliveryFailure(c.env, inserted.id, message);
      return c.json({ error: message, id: inserted.id, status: inserted.status }, 502);
    }
  }
  // Notify boss-agents for API channel messages (agent-as-boss)
  if (channel === 'api' && !queuedForQuietHours) {
    c.executionCtx.waitUntil(notifyBossAgents(c.env, agentId, inserted));
  }
  // Notify target agent for agent-to-agent messages via callback
  if (targetAgentId) {
    c.executionCtx.waitUntil(notifyTargetAgent(c.env, targetAgentId, inserted));
  }
  if (options && direction === 'agent_to_boss') {
    c.executionCtx.waitUntil(expirePreviousOptions(c.env, agentId, sessionId, inserted.id).catch(() => {}));
  }
  c.executionCtx.waitUntil(logAudit(c.env, 'agent', agentId, 'message.send', 'message', inserted.id, JSON.stringify({ direction, priority, mode })));
  const response: Record<string, unknown> = { id: inserted.id, status: inserted.status, created_at: inserted.created_at };
  if (targetWarning) response.warning = targetWarning;
  return c.json(response, 201);
});

routes.get('/', async (c) => {
  const agentId = getAgentId(c);
  const unread = c.req.query('unread') === 'true';
  const directionParam = c.req.query('direction') || undefined;
  const direction = validateOption<Direction>(directionParam, ['agent_to_boss', 'boss_to_agent', 'agent_to_agent']);
  const statusParam = unread ? undefined : c.req.query('status') || undefined;
  const status = validateOption<Status>(statusParam, ['sent', 'delivered', 'read', 'replied']);
  const priorityFilter = parsePriorityFilter(c.req.query('priority'));
  const typeFilter = c.req.query('type') || undefined;
  const sessionFilter = c.req.query('session') || undefined;
  const fromFilter = c.req.query('from') || undefined;
  const targetSessionFilter = c.req.query('target_session') || undefined;
  const searchFilter = c.req.query('search') || undefined;
  const limit = clampNumber(c.req.query('limit'), 20, MAX_LIMIT);
  const offset = Math.max(Number(c.req.query('offset') ?? '0'), 0);
  const { where, binds } = buildFilters(agentId, direction, status, priorityFilter, typeFilter, sessionFilter, unread, fromFilter, targetSessionFilter, searchFilter);
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
  const canReply = parent.direction === 'agent_to_agent'
    ? parent.agent_id === agentId || parent.target_agent_id === agentId
    : parent.agent_id === agentId;
  if (!canReply) {
    return c.text('forbidden', 403);
  }
  const payload = await c.req.json<Record<string, unknown>>();
  const body = typeof payload.body === 'string' ? payload.body.trim() : '';
  if (!body) {
    return c.text('body is required', 400);
  }
  // For agent_to_agent messages, reply direction is also agent_to_agent (back to sender)
  const replyDirection: Direction = parent.direction === 'agent_to_agent'
    ? 'agent_to_agent'
    : parent.direction === 'boss_to_agent' ? 'agent_to_boss' : 'boss_to_agent';
  const replyTargetAgentId = replyDirection === 'agent_to_agent' ? parent.agent_id : null;
  const replyTargetSessionId = replyDirection === 'agent_to_agent' ? parent.session_id : null;
  const inserted = await c.env.DB
    .prepare(
      'INSERT INTO messages (agent_id, direction, mode, channel, body, status, priority, reply_to, target_agent_id, target_session_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING *'
    )
    .bind(agentId, replyDirection, 'async', parent.channel, body, 'sent', 'normal', parent.id, replyTargetAgentId, replyTargetSessionId)
    .first<MessageRow>();
  if (!inserted) {
    return c.text('failed to persist', 500);
  }
  if (replyDirection === 'agent_to_boss' && parent.channel) {
    try {
      const channelConfig = await selectChannelConfig(c.env, agentId, parent.channel as Channel);
      const agentRow = await c.env.DB.prepare('SELECT name, avatar_url FROM api_keys WHERE id = ?').bind(agentId).first<{ name: string; avatar_url: string | null }>();
      let replyDisplayName = agentRow?.name ?? 'agent';
      let sessionLabel: string | null = null;
      if (parent.session_id) {
        const sess = await c.env.DB.prepare('SELECT label FROM sessions WHERE id = ?').bind(parent.session_id).first<{ label: string | null }>();
        sessionLabel = sess?.label ?? null;
        if (sessionLabel) replyDisplayName = `${sessionLabel} (${replyDisplayName})`;
      }
      if (channelConfig.channel === 'telegram' && parent.session_id) {
        await ensureTopicForSession(
          c.env,
          parent.session_id,
          agentRow?.name ?? 'agent',
          sessionLabel,
          requireTelegramConfig(channelConfig.config),
        );
      }
      const telegramReplyId = extractTelegramMessageId(parent.metadata);
      const result = await deliverWithRetry(() =>
        deliverReply(
          channelConfig.channel,
          channelConfig.config,
          replyDisplayName,
          body,
          telegramReplyId,
          agentRow?.avatar_url ?? undefined,
          c.env,
          parent.session_id,
        )
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
    } catch (error) {
      await persistDeliveryFailure(c.env, inserted.id, getDeliveryErrorMessage(error));
    }
  }
  await c.env.DB
    .prepare("UPDATE messages SET status = 'replied', updated_at = datetime('now') WHERE id = ?")
    .bind(parent.id)
    .run();
  if (replyTargetAgentId) {
    c.executionCtx.waitUntil(notifyTargetAgent(c.env, replyTargetAgentId, inserted));
  }
  c.executionCtx.waitUntil(logAudit(c.env, 'agent', agentId, 'message.reply', 'message', parent.id));
  return c.json(mapMessageRow(inserted), 201);
});

routes.post('/:id/forward', async (c) => {
  const agentId = getAgentId(c);
  const original = await fetchMessageRow(c.env, agentId, c.req.param('id'));
  if (!original) {
    return c.text('not found', 404);
  }
  if (original.agent_id !== agentId) {
    return c.text('forbidden', 403);
  }
  const payload = await c.req.json<Record<string, unknown>>();
  const targetChannel = validateForwardChannel(payload.channel);
  if (!targetChannel) {
    return c.text('channel must be discord or telegram', 400);
  }
  try {
    const forwarded = await forwardMessage(c.env, original, targetChannel);
    c.executionCtx.waitUntil(logAudit(c.env, 'agent', agentId, 'message.forward', 'message', original.id, targetChannel));
    return c.json(mapMessageRow(forwarded), 201);
  } catch (error) {
    const message = error instanceof Error ? error.message : 'forward failed';
    const status = message === 'no channel configured' ? 400 : message === 'cannot forward boss messages' ? 403 : 502;
    return c.text(message, status);
  }
});

routes.patch('/:id', async (c) => {
  const agentId = getAgentId(c);
  const payload = await c.req.json<Record<string, unknown>>();
  const body = typeof payload.body === 'string' ? payload.body.trim() : undefined;
  const status = validateOption<Status>(payload.status, ['sent', 'delivered', 'read', 'replied', 'expired']);
  if (!status && !body) {
    return c.text('status or body is required', 400);
  }
  const existing = await fetchMessageRow(c.env, agentId, c.req.param('id'));
  if (!existing) {
    return c.text('not found', 404);
  }
  if (existing.agent_id !== agentId) {
    return c.text('only message owner can update message', 403);
  }
  if (body && existing.direction !== 'agent_to_boss') {
    return c.text('only agent_to_boss messages can be edited', 403);
  }

  const updates: string[] = ["updated_at = datetime('now')"];
  const binds: unknown[] = [];

  if (status) {
    const allowed = VALID_TRANSITIONS[existing.status];
    if (!allowed || !allowed.includes(status)) {
      return c.text(`invalid status transition from ${existing.status} to ${status}`, 400);
    }
    updates.push('status = ?');
    binds.push(status);
  }

  if (body) {
    updates.push('body = ?');
    binds.push(body);
  }

  binds.push(existing.id);

  const updated = await c.env.DB
    .prepare(
      `UPDATE messages SET ${updates.join(', ')} WHERE id = ? RETURNING *`
    )
    .bind(...binds)
    .first<MessageRow>();

  if (!updated) {
    return c.text('update failed', 500);
  }
  if (body) {
    c.executionCtx.waitUntil(propagateMessageEdit(c.env, updated));
    c.executionCtx.waitUntil(
      logAudit(c.env, 'agent', agentId, 'message.edit', 'message', updated.id, JSON.stringify({ channel: updated.channel }))
    );
  }
  return c.json(mapMessageRow(updated));
});

// Bulk mark all unread messages as read
routes.post('/mark-all-read', async (c) => {
  const agentId = getAgentId(c);
  const result = await c.env.DB
    .prepare("UPDATE messages SET status = 'read', updated_at = datetime('now') WHERE agent_id = ? AND status IN ('sent', 'delivered')")
    .bind(agentId)
    .run();
  const count = result.meta.changes ?? 0;
  return c.json({ marked: count });
});

// React and reactions endpoints are in reactions.ts
routes.route('/', reactionsRouter);

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
      const finalCheck = await fetchMessageWithReplies(c.env, agentId, message.id);
      if (finalCheck && (finalCheck.replies?.length ?? 0) > 0) {
        return c.json(finalCheck);
      }
      c.executionCtx.waitUntil(expireMessageOptions(c.env, agentId, message).catch(() => {}));
      return c.json(finalCheck ?? { ...mapMessageRow(message), replies: [] });
    }
    await delay(Math.min(WAIT_INTERVAL_MS, deadline - Date.now()));
  }
});

export const messagesRouter = routes;
