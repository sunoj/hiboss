// Agent reply endpoint and legacy reply delivery.
// Exports messageReplyRouter; depends on message helpers and destination dispatch.
import { MESSAGE_METADATA_OBJECT_SQL } from './message-reactions';
import { Hono, type Context } from 'hono';
import { logAudit } from '../audit';
import { getAgentId, getAgentKeyId } from '../middleware/auth';
import { actionContent, audienceOf, authenticateAgentMessage, signedIdempotencyKey } from '../message-security';
import { findByIdempotencyKey } from './message-queries';
import { notifyTargetAgent } from '../notify';
import { createMessageId, insertMessageWithEvent } from '../session-events';
import type { Channel, Direction, Env, MessageRow } from '../types';
import { OPEN_MESSAGE_STATUS, SENT_MESSAGE_STATUS } from '../message-status';
import { getDeliveryErrorMessage, persistDeliveryFailure } from './delivery';
import {
  deliverReply,
  deliverWithRetry,
  extractTelegramMessageId,
  fetchMessageRow,
  mapMessageRow,
  replyTargetSession,
  requireTelegramConfig,
  selectChannelConfig,
} from './message-helpers';
import { ensureTopicForSession } from './session-channels';

import { destinationsMode, dispatchDestinations } from '../delivery';
const routes = new Hono<{ Bindings: Env }>();
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
    : 'agent_to_boss';
  const replyTargetAgentId = replyDirection === 'agent_to_agent' ? parent.agent_id : null;
  const replyTargetSessionId = replyDirection === 'agent_to_agent' ? replyTargetSession(parent) : null;
  const audience = audienceOf(replyDirection, replyTargetAgentId, replyTargetSessionId);
  const auth = await authenticateAgentMessage({
    env: c.env, agentId, agentKeyId: getAgentKeyId(c), signedMessage: payload.signed_message,
    content: actionContent({ kind: 'reply', message_id: parent.id, audience }, body),
  });
  if (!auth.ok) return c.text(auth.error, auth.status);
  const idempotencyKey = auth.signed ? signedIdempotencyKey(auth.signed) : null;
  if (idempotencyKey) {
    const existing = await findByIdempotencyKey(c.env, agentId, idempotencyKey);
    if (existing) return c.json(mapMessageRow(existing), 200);
  }
  return persistReply(c, parent, body, replyDirection, replyTargetAgentId,
    replyTargetSessionId, auth.metadata, idempotencyKey);
});

async function persistReply(
  c: Context<{ Bindings: Env }>, parent: MessageRow, body: string, replyDirection: Direction,
  replyTargetAgentId: string | null, replyTargetSessionId: string | null,
  metadata: Record<string, unknown>, idempotencyKey: string | null,
): Promise<Response> {
  const agentId = getAgentId(c);
  const inserted = await insertMessageWithEvent(
    c.env,
    `INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority,
      session_id, reply_to, target_agent_id, target_session_id, metadata, idempotency_key)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING *`,
    [createMessageId(), agentId, replyDirection, 'async', parent.channel, body, 'sent', 'normal',
      replyTargetSession(parent), parent.id, replyTargetAgentId, replyTargetSessionId,
      JSON.stringify(metadata), idempotencyKey],
    replyTargetSession(parent),
  );
  if (!inserted) {
    return c.text('failed to persist', 500);
  }
  if (replyDirection === 'agent_to_boss') await sendBossReply(c, inserted, parent, body);
  if (parent.direction !== 'agent_to_boss') {
    await c.env.DB
      .prepare(`UPDATE messages SET status = 'replied', updated_at = datetime('now') WHERE id = ? AND ${OPEN_MESSAGE_STATUS}`)
      .bind(parent.id).run();
  }
  if (replyTargetAgentId) {
    c.executionCtx.waitUntil(notifyTargetAgent(c.env, replyTargetAgentId, inserted));
  }
  c.executionCtx.waitUntil(logAudit(c.env, 'agent', agentId, 'message.reply', 'message', parent.id));
  return c.json(mapMessageRow(inserted), 201);
}

export const messageReplyRouter = routes;

async function sendBossReply(c: Context<{ Bindings: Env }>, inserted: MessageRow, parent: MessageRow, body: string): Promise<void> {
  const agentId = inserted.agent_id;
  if (destinationsMode(c.env.DESTINATIONS_MODE) === 'on') {
    await dispatchDestinations(c.env, inserted);
  }
  if (parent.channel && destinationsMode(c.env.DESTINATIONS_MODE) !== 'on') {
    try {
      const channelConfig = await selectChannelConfig(c.env, agentId, parent.channel as Channel);
      await dispatchDestinations(c.env, inserted, [channelConfig]);
      const agentRow = await c.env.DB.prepare('SELECT name, avatar_url FROM api_keys WHERE id = ?').bind(agentId).first<{ name: string; avatar_url: string | null }>();
      let replyDisplayName = agentRow?.name ?? 'agent';
      let sessionLabel: string | null = null;
      if (inserted.session_id) {
        const sess = await c.env.DB.prepare('SELECT label FROM sessions WHERE id = ?').bind(inserted.session_id).first<{ label: string | null }>();
        sessionLabel = sess?.label ?? null;
        if (sessionLabel) replyDisplayName = `${sessionLabel} (${replyDisplayName})`;
      }
      if (channelConfig.channel === 'telegram' && inserted.session_id) {
        await ensureTopicForSession(
          c.env,
          inserted.session_id,
          agentRow?.name ?? 'agent',
          sessionLabel,
          requireTelegramConfig(channelConfig.config),
        );
      }
      const telegramReplyId = extractTelegramMessageId(parent.metadata);
      const result = await deliverWithRetry(() =>
        deliverReply(
          channelConfig.channel, channelConfig.config, replyDisplayName, body, telegramReplyId,
          agentRow?.avatar_url ?? undefined, c.env, inserted.session_id,
        )
      );
      if (result.delivered) {
        await markReplyDelivered(c.env, inserted.id, result.telegramMessageId,
          channelConfig.channel === 'telegram' ? channelConfig.config.chat_id : undefined,
          result.discordMessageId);
      }
    } catch (error) {
      await persistDeliveryFailure(c.env, inserted.id, getDeliveryErrorMessage(error));
    }
  }
}

async function markReplyDelivered(
  env: Env, messageId: string, telegramMessageId?: number, telegramChatId?: unknown,
  discordMessageId?: string,
): Promise<void> {
  const metadata: Record<string, unknown> = {};
  if (telegramMessageId) {
    metadata['telegram_message_id'] = telegramMessageId;
    if (typeof telegramChatId === 'string') metadata['telegram_chat_id'] = telegramChatId;
  }
  if (discordMessageId) metadata['discord_message_id'] = discordMessageId;
  await env.DB.prepare(`UPDATE messages SET status = 'delivered',
    metadata = json_patch(${MESSAGE_METADATA_OBJECT_SQL}, json(?)), updated_at = datetime('now')
    WHERE id = ? AND ${SENT_MESSAGE_STATUS}`)
    .bind(JSON.stringify(metadata), messageId).run();
}
