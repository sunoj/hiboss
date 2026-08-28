// Periodic sweeps for expiring options messages and draining quiet-hours delivery queue.
// Exports the scheduled handler used by the Worker cron entrypoint.
// Depends on D1, message expiry helpers, and the shared agent delivery helper.

import type { Env, MessageRow } from './types';
import { getDeliveryErrorMessage, persistDeliveryFailure } from './routes/delivery';
import { deliverAgentMessage } from './routes/agent-delivery';
import { expireMessageOptions } from './routes/message-options';

const BATCH_SIZE = 50;
const MAX_QUEUE_ATTEMPTS = 3;
const PROCESSING_TIMEOUT_MS = 5 * 60 * 1000;

interface DeliveryQueueRow {
  id: string;
  message_id: string;
  agent_id: string;
  channel: 'discord' | 'telegram' | 'email' | 'api';
  config: string;
  scheduled_at: string;
  attempts: number;
}

interface QueuedMessageRow extends MessageRow {
  agent_name: string | null;
  avatar_url: string | null;
}

export async function handleScheduled(env: Env): Promise<void> {
  const now = new Date().toISOString();
  await expireDueOptions(env, now);
  await drainDeliveryQueue(env, now);
}

async function expireDueOptions(env: Env, now: string): Promise<void> {
  const rows = await env.DB
    .prepare(
      `SELECT * FROM messages WHERE expires_at IS NOT NULL AND expires_at < ? AND status IN ('queued', 'sent', 'delivered', 'read') AND json_extract(metadata, '$.options') IS NOT NULL LIMIT ?`
    )
    .bind(now, BATCH_SIZE)
    .all<MessageRow>();

  for (const row of rows.results ?? []) {
    try {
      await expireMessageOptions(env, row.agent_id, row);
    } catch {
      console.error(`Failed to expire message ${row.id}`);
    }
  }
}

async function drainDeliveryQueue(env: Env, now: string): Promise<void> {
  await reclaimStaleQueueItems(env, now);
  await retryFailedQueueItems(env, now);
  const rows = await env.DB
    .prepare(
      `SELECT id, message_id, agent_id, channel, config, scheduled_at, attempts
       FROM delivery_queue
       WHERE status = 'pending' AND scheduled_at <= ?
       ORDER BY scheduled_at ASC
       LIMIT ?`
    )
    .bind(now, BATCH_SIZE)
    .all<DeliveryQueueRow>();

  for (const row of rows.results ?? []) {
    const locked = await markQueueProcessing(env, row.id, now);
    if (!locked) continue;
    try {
      await deliverQueuedMessage(env, row);
      await markQueueDelivered(env, row.id);
    } catch (error) {
      const message = getDeliveryErrorMessage(error);
      await persistDeliveryFailure(env, row.message_id, message);
      await markQueueFailed(env, row.id, message, computeRetryAt(now, row.attempts + 1));
    }
  }
}

async function deliverQueuedMessage(env: Env, row: DeliveryQueueRow): Promise<void> {
  const message = await fetchQueuedMessage(env, row.message_id);
  if (!message) {
    throw new Error('queued message not found');
  }

  const metadata = parseMetadata(message.metadata);
  const options = parseOptions(metadata?.['options']);
  const result = await deliverAgentMessage(
    env,
    { channel: row.channel, config: JSON.parse(row.config) as Record<string, unknown> },
    {
      agentId: message.agent_id,
      agentName: message.agent_name ?? 'agent',
      body: message.body,
      sessionId: message.session_id,
      avatarUrl: message.avatar_url ?? undefined,
      fileUrl: typeof metadata?.['file_url'] === 'string' ? metadata['file_url'] : undefined,
      inlineKeyboard: options ? buildInlineKeyboard(message.id, options) : undefined,
    },
  );
  if (!result.delivered) {
    throw new Error('delivery failure');
  }
  await markMessageDelivered(env, message, metadata, result.telegramMessageId, result.discordMessageId);
}

async function fetchQueuedMessage(env: Env, messageId: string): Promise<QueuedMessageRow | null> {
  return env.DB
    .prepare(
      `SELECT messages.*, api_keys.name AS agent_name, api_keys.avatar_url
       FROM messages
       LEFT JOIN api_keys ON api_keys.id = messages.agent_id
       WHERE messages.id = ?`
    )
    .bind(messageId)
    .first<QueuedMessageRow>();
}

async function markMessageDelivered(
  env: Env,
  message: QueuedMessageRow,
  metadata: Record<string, unknown> | null,
  telegramMessageId?: number,
  discordMessageId?: string,
): Promise<void> {
  const updates: string[] = ["status = 'delivered'", "updated_at = datetime('now')"];
  const binds: Array<string | number> = [];
  const nextMetadata = metadata ? { ...metadata } : {};

  if (telegramMessageId) nextMetadata['telegram_message_id'] = telegramMessageId;
  if (discordMessageId) nextMetadata['discord_message_id'] = discordMessageId;
  if (Object.keys(nextMetadata).length > 0) {
    updates.push('metadata = ?');
    binds.push(JSON.stringify(nextMetadata));
  }

  binds.push(message.id);
  await env.DB
    .prepare(`UPDATE messages SET ${updates.join(', ')} WHERE id = ?`)
    .bind(...binds)
    .run();
}

async function reclaimStaleQueueItems(env: Env, now: string): Promise<void> {
  await env.DB
    .prepare("UPDATE delivery_queue SET status = 'pending', scheduled_at = ?, error = NULL WHERE status = 'processing' AND scheduled_at <= ?")
    .bind(now, new Date(Date.parse(now) - PROCESSING_TIMEOUT_MS).toISOString())
    .run();
}

async function retryFailedQueueItems(env: Env, now: string): Promise<void> {
  await env.DB
    .prepare("UPDATE delivery_queue SET status = 'pending' WHERE status = 'failed' AND attempts < ? AND scheduled_at <= ?")
    .bind(MAX_QUEUE_ATTEMPTS, now)
    .run();
}

async function markQueueProcessing(env: Env, queueId: string, now: string): Promise<boolean> {
  const result = await env.DB
    .prepare("UPDATE delivery_queue SET status = 'processing', attempts = attempts + 1, scheduled_at = ?, error = NULL WHERE id = ? AND status = 'pending'")
    .bind(now, queueId)
    .run();
  return (result.meta.changes ?? 0) > 0;
}

async function markQueueDelivered(env: Env, queueId: string): Promise<void> {
  await env.DB
    .prepare("UPDATE delivery_queue SET status = 'delivered', error = NULL WHERE id = ? AND status = 'processing'")
    .bind(queueId)
    .run();
}

async function markQueueFailed(env: Env, queueId: string, error: string, nextRetryAt: string): Promise<void> {
  await env.DB
    .prepare("UPDATE delivery_queue SET status = 'failed', error = ?, scheduled_at = ? WHERE id = ? AND status = 'processing'")
    .bind(error, nextRetryAt, queueId)
    .run();
}

function parseMetadata(value: string | null): Record<string, unknown> | null {
  if (!value) return null;
  try {
    return JSON.parse(value) as Record<string, unknown>;
  } catch {
    return null;
  }
}

function parseOptions(value: unknown): string[] | null {
  if (!Array.isArray(value)) return null;
  return value.every((item) => typeof item === 'string') ? value : null;
}

function buildInlineKeyboard(messageId: string, options: string[]): { text: string; callback_data: string }[][] {
  return options.map((option) => [{ text: option, callback_data: `${messageId.slice(0, 12)}:${option}` }]);
}

function computeRetryAt(now: string, attempts: number): string {
  const backoffMs = Math.max(60_000, 2 ** Math.max(attempts - 1, 0) * 60_000);
  return new Date(Date.parse(now) + backoffMs).toISOString();
}
