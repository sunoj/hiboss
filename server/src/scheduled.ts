// Periodic sweeps for expiring options messages and draining quiet-hours delivery queue.
// Exports the scheduled handler used by the Worker cron entrypoint.
// Depends on D1, message expiry helpers, and the native delivery queue.

import type { Env, MessageRow } from './types';
import { SENT_MESSAGE_STATUS } from './message-status';
import { getDeliveryErrorMessage, persistDeliveryFailure } from './routes/delivery';
import { expireMessageOptions } from './routes/message-options';
import { expireStaleAsks } from './abandoned-asks';
import { notifyBossAgents } from './notify';
import { destinationsMode, drainDestinationDeliveries } from './delivery';
import { purgeLiveActivityTokens } from './push/live-activity';
import { ResolutionSweep, type Announce } from './push/resolution';

const BATCH_SIZE = 50;
const MAX_QUEUE_ATTEMPTS = 3;
const PROCESSING_TIMEOUT_MS = 5 * 60 * 1000;

interface DeliveryQueueRow {
  id: string;
  message_id: string;
  attempts: number;
}

/** One cron run; `minute` (UTC) selects the hourly steps, which run in the first five minutes. */
export async function handleScheduled(env: Env, minute = new Date().getUTCMinutes()): Promise<void> {
  const now = new Date().toISOString();
  await cleanupPairingCodes(env, now);
  // Resolutions go out last and capped, so their pushes never spend the transitions' budget.
  const resolutions = new ResolutionSweep();
  try {
    await expireDueOptions(env, now, resolutions.announce);
    // Hourly is enough for a one-day rule (pending inputs already exclude stale asks), and
    // the sweep query scans messages; isolate it so a failure never blocks delivery.
    if (minute < 5) {
      try {
        await expireStaleAsks(env, resolutions.announce);
      } catch {
        console.error('Failed to sweep abandoned asks');
      }
    }
    if (destinationsMode(env.DESTINATIONS_MODE) === 'on') await drainDestinationDeliveries(env);
    else await drainDeliveryQueue(env, now);
  } finally {
    await resolutions.flush(env);
  }
}

async function cleanupPairingCodes(env: Env, now: string): Promise<void> {
  await env.DB.prepare('DELETE FROM boss_pairing_codes WHERE expires_at <= ?').bind(now).run();
  await env.DB.prepare('DELETE FROM signin_requests WHERE expires_at <= ?').bind(now).run();
  // Delta-syncing clients resynchronize fully well within this window.
  await env.DB.prepare("DELETE FROM session_removals WHERE removed_at < datetime(?, '-30 days')").bind(now).run();
  await purgeLiveActivityTokens(env);
}

async function expireDueOptions(env: Env, now: string, announce: Announce): Promise<void> {
  const rows = await env.DB
    .prepare(
      `SELECT * FROM messages WHERE expires_at IS NOT NULL AND expires_at < ?
       AND status IN ('sent', 'delivered', 'read')
       AND (json_extract(metadata, '$.options') IS NOT NULL OR mode = 'blocking')
       ORDER BY expires_at ASC, id ASC LIMIT ?`
    )
    .bind(now, BATCH_SIZE)
    .all<MessageRow>();

  for (const row of rows.results ?? []) {
    try {
      await expireMessageOptions(env, row.agent_id, row, announce);
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
      `SELECT id, message_id, attempts
       FROM delivery_queue
       WHERE status = 'pending' AND scheduled_at <= ?
         AND channel = 'api' AND json_extract(config, '$.native_only') = 1
       ORDER BY scheduled_at ASC
       LIMIT ?`
    )
    .bind(now, BATCH_SIZE)
    .all<DeliveryQueueRow>();

  for (const row of rows.results ?? []) {
    const locked = await markQueueProcessing(env, row.id, now);
    if (!locked) continue;
    try {
      const message = await fetchQueuedMessage(env, row.message_id);
      if (!message) throw new Error('queued message not found');
      if (isClosedAsk(message, now)) {
        await markQueueSkipped(env, row.id);
        continue;
      }
      await markMessageDelivered(env, message);
      await markQueueDelivered(env, row.id);
      // The same boss-agent callback and device push an immediate send triggers.
      if (message.direction === 'agent_to_boss') await notifyBossAgents(env, message.agent_id, message);
    } catch (error) {
      const message = getDeliveryErrorMessage(error);
      await persistDeliveryFailure(env, row.message_id, message);
      await markQueueFailed(env, row.id, message, computeRetryAt(now, row.attempts + 1));
    }
  }
}

/** An ask answered, expired, or past its deadline while queued no longer needs sending. */
function isClosedAsk(message: MessageRow, now: string): boolean {
  if (message.status === 'replied' || message.status === 'expired') return true;
  return !!message.expires_at && Date.parse(message.expires_at) <= Date.parse(now);
}

async function fetchQueuedMessage(env: Env, messageId: string): Promise<MessageRow | null> {
  return env.DB.prepare('SELECT * FROM messages WHERE id = ?').bind(messageId).first<MessageRow>();
}

async function markMessageDelivered(env: Env, message: MessageRow): Promise<void> {
  await env.DB.prepare(`UPDATE messages SET status = 'delivered', updated_at = datetime('now')
    WHERE id = ? AND ${SENT_MESSAGE_STATUS}`).bind(message.id).run();
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
    .prepare(`UPDATE delivery_queue SET status = 'processing', attempts = attempts + 1, scheduled_at = ?, error = NULL
      WHERE id = ? AND status = 'pending'
      AND channel = 'api' AND json_extract(config, '$.native_only') = 1`)
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

async function markQueueSkipped(env: Env, queueId: string): Promise<void> {
  await env.DB
    .prepare("UPDATE delivery_queue SET status = 'failed', attempts = ?, error = ? WHERE id = ? AND status = 'processing'")
    .bind(MAX_QUEUE_ATTEMPTS, 'ask closed before delivery', queueId)
    .run();
}

async function markQueueFailed(env: Env, queueId: string, error: string, nextRetryAt: string): Promise<void> {
  await env.DB
    .prepare("UPDATE delivery_queue SET status = 'failed', error = ?, scheduled_at = ? WHERE id = ? AND status = 'processing'")
    .bind(error, nextRetryAt, queueId)
    .run();
}

function computeRetryAt(now: string, attempts: number): string {
  const backoffMs = Math.max(60_000, 2 ** Math.max(attempts - 1, 0) * 60_000);
  return new Date(Date.parse(now) + backoffMs).toISOString();
}
