// Records shadow parity and executes resumable destination delivery with bounded retries.
// Exports dispatch and cron entrypoints; depends on resolver, adapters, and D1 atomic claims.
import type { Channel, Env, MessageRow } from '../types';
import { logAudit } from '../audit';
import { resolveDiscordChannelId } from '../routes/agent-delivery';
import { groupTargets, recordTarget, mirrorMerged, chatKey, type DeliveryRow } from './targets';
import { sendDestination } from './adapters';
import { resolveDestinations } from './destinations';
import { destinationsMode, type ResolvedDestination } from './types';

const MAX_ATTEMPTS = 3;
const LEASE_MS = 5 * 60_000;
const BATCH_SIZE = 50;
type LegacyConfig = { channel: Channel; config: Record<string, unknown> };

export async function dispatchDestinations(env: Env, message: MessageRow, legacy: LegacyConfig[] = []): Promise<void> {
  const mode = destinationsMode(env.DESTINATIONS_MODE);
  if (mode === 'off' || message.direction !== 'agent_to_boss') return;
  try {
    const now = new Date();
    const destinations = await resolveDestinations(env, message, now);
    for (const group of await groupTargets(env, destinations)) {
      const destination = group.destinations[0];
      const due = mode === 'on' && destination.kind !== 'native_live' ? destination.nextAttemptAt ?? now.toISOString() : null;
      const row = await recordTarget(env, message.id, group, due);
      if (row && due && due <= now.toISOString()) await attemptDelivery(env, row, message, destination, now);
    }
    if (mode === 'shadow') await compareShadow(env, message, legacy, destinations);
  } catch (error) {
    if (mode === 'on') throw error;
    // Shadow failures cannot alter the legacy response or notification behavior.
    console.error('Destination shadow recording failed', message.id, error instanceof Error ? error.name : 'Error');
  }
}

async function compareShadow(env: Env, message: MessageRow, legacy: LegacyConfig[], destinations: ResolvedDestination[]): Promise<void> {
  const legacyRoutes = await Promise.all(legacy.map(async row => {
    const channelId = row.channel === 'discord' ? await resolveDiscordChannelId(env, row.config, message.session_id) : undefined;
    const config = channelId && channelId !== row.config.channel_id
      ? { ...row.config, channel_id: channelId, thread_id: channelId } : row.config;
    return { kind: row.channel, config };
  }));
  const oldChats = await chatSet(legacyRoutes);
  const newChats = await chatSet(destinations.map(row => ({
    kind: row.kind === 'telegram_chat' ? 'telegram' : row.kind === 'discord_channel' ? 'discord' : row.kind,
    config: row.config,
  })));
  if (JSON.stringify(oldChats) === JSON.stringify(newChats)) return;
  await logAudit(env, 'system', 'destinations', 'destination_shadow', 'message', message.id,
    JSON.stringify({ legacy_chats: oldChats, destination_chats: newChats }));
}

async function chatSet(rows: { kind: string; config: Record<string, unknown> }[]): Promise<string[]> {
  const keys: string[] = [];
  for (const { kind, config } of rows) {
    if (kind !== 'telegram' && kind !== 'discord') continue;
    keys.push(await chatKey(kind, config));
  }
  return [...new Set(keys)].sort();
}

export async function drainDestinationDeliveries(env: Env, now = new Date()): Promise<void> {
  if (destinationsMode(env.DESTINATIONS_MODE) !== 'on') return;
  const rows = await env.DB.prepare(`SELECT id, message_id, destination_id, attempts, next_attempt_at, external_target
    FROM message_deliveries WHERE merged_into IS NULL AND status IN ('queued', 'failed') AND next_attempt_at <= ?
    ORDER BY next_attempt_at, id LIMIT ?`).bind(now.toISOString(), BATCH_SIZE).all<DeliveryRow>();
  for (const row of rows.results) {
    const message = await env.DB.prepare('SELECT * FROM messages WHERE id = ?').bind(row.message_id).first<MessageRow>();
    const destinations = message ? await resolveDestinations(env, message, now) : [];
    const groups = await groupTargets(env, destinations);
    const destination = row.external_target
      ? groups.find(group => group.key === row.external_target)?.destinations[0]
      : destinations.find(item => item.id === row.destination_id);
    if (!message || !destination || message.status === 'expired' || (message.expires_at && message.expires_at <= now.toISOString()) || row.attempts >= MAX_ATTEMPTS) {
      await env.DB.prepare("UPDATE message_deliveries SET status = 'failed', next_attempt_at = NULL, last_error = 'no longer eligible or retry limit reached', updated_at = ? WHERE id = ? AND next_attempt_at = ?")
        .bind(now.toISOString(), row.id, row.next_attempt_at).run();
      await mirrorMerged(env, row.id);
      continue;
    }
    if (destination.nextAttemptAt) {
      await env.DB.prepare('UPDATE message_deliveries SET next_attempt_at = ?, updated_at = ? WHERE id = ? AND next_attempt_at = ?')
        .bind(destination.nextAttemptAt, now.toISOString(), row.id, row.next_attempt_at).run();
      continue;
    }
    await attemptDelivery(env, row, message, destination, now);
  }
}

async function attemptDelivery(env: Env, row: DeliveryRow, message: MessageRow, destination: ResolvedDestination, now: Date): Promise<void> {
  const lease = new Date(now.getTime() + LEASE_MS).toISOString();
  const claimed = await env.DB.prepare(`UPDATE message_deliveries SET attempts = attempts + 1, next_attempt_at = ?, updated_at = ?
    WHERE id = ? AND status IN ('queued', 'failed') AND attempts = ? AND next_attempt_at = ?`)
    .bind(lease, now.toISOString(), row.id, row.attempts, row.next_attempt_at).run();
  if (!claimed.meta.changes) return;
  try {
    const externalId = await sendDestination(env, destination, message);
    await env.DB.prepare(`UPDATE message_deliveries SET status = 'sent', external_message_id = ?, next_attempt_at = NULL,
      last_error = NULL, updated_at = ? WHERE id = ? AND next_attempt_at = ?`)
      .bind(externalId, new Date().toISOString(), row.id, lease).run();
  } catch {
    // Adapter exceptions can contain credential-bearing URLs; persist a safe error only.
    const retryAt = row.attempts + 1 < MAX_ATTEMPTS ? new Date(now.getTime() + 2 ** row.attempts * 60_000).toISOString() : null;
    await env.DB.prepare(`UPDATE message_deliveries SET status = 'failed', next_attempt_at = ?, last_error = 'destination send failed',
      updated_at = ? WHERE id = ? AND next_attempt_at = ?`).bind(retryAt, new Date().toISOString(), row.id, lease).run();
  } finally {
    await mirrorMerged(env, row.id);
  }
}
