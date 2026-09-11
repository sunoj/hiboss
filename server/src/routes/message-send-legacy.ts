// Preserves legacy channel fan-out, quiet-hour queuing, and response semantics.
// Exports deliverLegacySend; depends on shared adapters and message metadata.
import type { Context } from 'hono';
import type { Env, Channel, MessageRow, OptionMedia } from '../types';
import { buildInlineKeyboard } from './message-helpers';
import { deliverAgentMessage } from './agent-delivery';
import { getAgentQuietHoursEnd } from './quiet-hours';
import { getDeliveryErrorMessage, persistDeliveryFailure } from './delivery';
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

export async function deliverLegacySend(c: Context<{ Bindings: Env }>, inserted: MessageRow, channelConfigs: { channel: Channel; config: Record<string, unknown> }[], options: string[] | undefined, optionMedia: OptionMedia[] | undefined, fileUrl: string | undefined, avatarUrl: string | undefined): Promise<Response | boolean> {
  const { agent_id: agentId, direction, body, session_id: sessionId, priority } = inserted;
  const metadata = inserted.metadata ? JSON.parse(inserted.metadata) as Record<string, unknown> : null;
  const isUrgent = priority === 'high' || priority === 'critical';
  let queuedForQuietHours = false;
  if (channelConfigs.length > 0 && direction === 'agent_to_boss' && !isUrgent) {
    const quietHoursEnd = await getAgentQuietHoursEnd(c.env, agentId);
    if (quietHoursEnd) {
      await enqueueDelivery(c.env, inserted.id, agentId, channelConfigs[0].channel, channelConfigs[0].config, quietHoursEnd);
      queuedForQuietHours = true;
    }
  }
  if (channelConfigs.length > 0 && direction !== 'agent_to_agent' && !queuedForQuietHours) {
    const agentRow = await c.env.DB.prepare('SELECT name FROM api_keys WHERE id = ?').bind(agentId).first<{ name: string }>();
    const resolvedAgentName = agentRow?.name ?? 'agent';
    const inlineKeyboard = options ? buildInlineKeyboard(inserted.id, options) : undefined;
    try {
      const results = await Promise.allSettled(
        channelConfigs.map((cc) =>
          deliverAgentMessage(c.env, cc, {
            agentId, agentName: resolvedAgentName, body, sessionId, inlineKeyboard,
            fileUrl, optionMedia, optionLabels: options, avatarUrl,
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
        await markLegacyDelivered(c.env, inserted.id, metadata, deliveryResults, isUrgent);
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
  return queuedForQuietHours;
}

interface LegacyResult { channel: Channel; ok: boolean; telegramMessageId?: number; discordMessageId?: string }
async function markLegacyDelivered(env: Env, messageId: string, metadata: Record<string, unknown> | null, deliveryResults: LegacyResult[], isUrgent: boolean): Promise<void> {
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
  if (isUrgent && deliveryResults.length > 1) {
    meta['delivery_results'] = deliveryResults.map((d) => ({ channel: d.channel, ok: d.ok }));
  }
  if (Object.keys(meta).length > 0) {
    updates.push('metadata = ?');
    binds.push(JSON.stringify(meta));
  }
  binds.push(messageId);
  await env.DB
    .prepare(`UPDATE messages SET ${updates.join(', ')} WHERE id = ?`)
    .bind(...binds)
    .run();
}
