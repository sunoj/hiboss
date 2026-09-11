// Agent reply endpoint and legacy reply delivery.
// Exports messageReplyRouter; depends on message helpers and destination dispatch.
import { Hono, type Context } from 'hono';
import { logAudit } from '../audit';
import { getAgentId } from '../middleware/auth';
import { notifyTargetAgent } from '../notify';
import { createMessageId, insertMessageWithEvent } from '../session-events';
import type { Channel, Direction, Env, MessageRow } from '../types';
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
    : parent.direction === 'boss_to_agent' ? 'agent_to_boss' : 'boss_to_agent';
  const replyTargetAgentId = replyDirection === 'agent_to_agent' ? parent.agent_id : null;
  const replyTargetSessionId = replyDirection === 'agent_to_agent' ? replyTargetSession(parent) : null;
  const inserted = await insertMessageWithEvent(
    c.env,
    'INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, reply_to, target_agent_id, target_session_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING *',
    [createMessageId(), agentId, replyDirection, 'async', parent.channel, body, 'sent', 'normal', parent.id, replyTargetAgentId, replyTargetSessionId],
    replyTargetSession(parent),
  );
  if (!inserted) {
    return c.text('failed to persist', 500);
  }
  if (replyDirection === 'agent_to_boss') await sendBossReply(c, inserted, parent, body);
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

export const messageReplyRouter = routes;

async function sendBossReply(c: Context<{ Bindings: Env }>, inserted: MessageRow, parent: MessageRow, body: string): Promise<void> {
  const agentId = inserted.agent_id;
  if (destinationsMode(c.env.DESTINATIONS_MODE) === 'on') {
    await c.env.DB.prepare('UPDATE messages SET session_id = ? WHERE id = ?').bind(parent.session_id, inserted.id).run();
    await dispatchDestinations(c.env, { ...inserted, session_id: parent.session_id });
  }
  if (parent.channel && destinationsMode(c.env.DESTINATIONS_MODE) !== 'on') {
    try {
      const channelConfig = await selectChannelConfig(c.env, agentId, parent.channel as Channel);
      await dispatchDestinations(c.env, { ...inserted, session_id: parent.session_id }, [channelConfig]);
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
          channelConfig.channel, channelConfig.config, replyDisplayName, body, telegramReplyId,
          agentRow?.avatar_url ?? undefined, c.env, parent.session_id,
        )
      );
      if (result.delivered) {
        await markReplyDelivered(c.env, inserted.id, result.telegramMessageId);
      }
    } catch (error) {
      await persistDeliveryFailure(c.env, inserted.id, getDeliveryErrorMessage(error));
    }
  }
}

async function markReplyDelivered(env: Env, messageId: string, telegramMessageId?: number): Promise<void> {
  const updates: string[] = ["status = 'delivered'", "updated_at = datetime('now')"];
  const binds: (string | number)[] = [];
  if (telegramMessageId) {
    updates.push('metadata = ?');
    binds.push(JSON.stringify({ telegram_message_id: telegramMessageId }));
  }
  binds.push(messageId);
  await env.DB
    .prepare(`UPDATE messages SET ${updates.join(', ')} WHERE id = ?`)
    .bind(...binds)
    .run();
}
