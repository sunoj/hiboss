// Streams actionable Boss options independently to every connected client.
// Exports: streamBossOptions for message fan-out and global resolution events.
// Depends on D1, MessageRow mapping, and Cloudflare writable streams.

import type { Env, MessageRow, Status } from '../types';
import { mapMessageRow } from './message-helpers';

const POLL_INTERVAL_MS = 3_000;
const KEEPALIVE_INTERVAL_MS = 15_000;
const MAX_DURATION_MS = 5 * 60 * 1_000;

interface TrackedOption {
  expiresAt: string | null;
}

interface OptionResolution {
  id: string;
  status: 'replied' | 'expired';
}

export async function streamBossOptions(
  writer: WritableStreamDefaultWriter,
  encoder: TextEncoder,
  env: Env,
  agentIds: string[],
): Promise<void> {
  const startedAt = Date.now();
  let lastKeepalive = Date.now();
  const trackedOptions = new Map<string, TrackedOption>();

  try {
    while (Date.now() - startedAt < MAX_DURATION_MS) {
      const now = new Date().toISOString();
      const activeOptions = await fetchActiveOptions(env, agentIds, now);
      await deliverNewOptions(writer, encoder, env, activeOptions, trackedOptions);
      await deliverResolutions(writer, encoder, env, activeOptions, trackedOptions, now);
      if (Date.now() - lastKeepalive >= KEEPALIVE_INTERVAL_MS) {
        await writer.write(encoder.encode(': keepalive\n\n'));
        lastKeepalive = Date.now();
      }
      await delay(POLL_INTERVAL_MS);
    }
  } catch {
    // The client disconnected; no shared delivery state needs cleanup.
  } finally {
    try { await writer.close(); } catch { /* already closed */ }
  }
}

async function fetchActiveOptions(
  env: Env,
  agentIds: string[],
  now: string,
): Promise<MessageRow[]> {
  const placeholders = agentIds.map(() => '?').join(', ');
  const result = await env.DB.prepare(
    `SELECT messages.*, api_keys.name AS agent_name
     FROM messages
     LEFT JOIN api_keys ON api_keys.id = messages.agent_id
     WHERE messages.agent_id IN (${placeholders})
       AND messages.direction = 'agent_to_boss'
       AND messages.status IN ('sent', 'delivered', 'read')
       AND json_extract(messages.metadata, '$.options') IS NOT NULL
       AND messages.expires_at > ?
     ORDER BY messages.created_at ASC`,
  ).bind(...agentIds, now).all<MessageRow>();
  return result.results ?? [];
}

async function deliverNewOptions(
  writer: WritableStreamDefaultWriter,
  encoder: TextEncoder,
  env: Env,
  activeOptions: MessageRow[],
  trackedOptions: Map<string, TrackedOption>,
): Promise<void> {
  for (const option of activeOptions) {
    if (trackedOptions.has(option.id)) continue;
    await writeEvent(writer, encoder, 'message', mapMessageRow(option));
    trackedOptions.set(option.id, { expiresAt: option.expires_at ?? null });
    await env.DB.prepare(
      "UPDATE messages SET status = 'delivered', updated_at = datetime('now') WHERE id = ? AND status = 'sent'",
    ).bind(option.id).run();
  }
}

async function deliverResolutions(
  writer: WritableStreamDefaultWriter,
  encoder: TextEncoder,
  env: Env,
  activeOptions: MessageRow[],
  trackedOptions: Map<string, TrackedOption>,
  now: string,
): Promise<void> {
  const activeIds = new Set(activeOptions.map((option) => option.id));
  for (const [messageId, tracked] of trackedOptions) {
    if (activeIds.has(messageId)) continue;
    const resolution = await resolveStatus(env, messageId, tracked, now);
    await writeEvent(writer, encoder, 'resolved', resolution);
    trackedOptions.delete(messageId);
  }
}

async function resolveStatus(
  env: Env,
  messageId: string,
  tracked: TrackedOption,
  now: string,
): Promise<OptionResolution> {
  if (tracked.expiresAt && tracked.expiresAt <= now) {
    return { id: messageId, status: 'expired' };
  }
  const row = await env.DB.prepare('SELECT status FROM messages WHERE id = ?')
    .bind(messageId)
    .first<{ status: Status }>();
  return { id: messageId, status: row?.status === 'expired' ? 'expired' : 'replied' };
}

async function writeEvent(
  writer: WritableStreamDefaultWriter,
  encoder: TextEncoder,
  event: 'message' | 'resolved',
  payload: unknown,
): Promise<void> {
  const data = JSON.stringify(payload);
  await writer.write(encoder.encode(`event: ${event}\ndata: ${data}\n\n`));
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
