// Streams actionable Boss options independently to every connected client.
// Exports: streamBossOptions for message fan-out and global resolution events.
// Depends on D1, MessageRow mapping, and Cloudflare writable streams.

import type { Channel, Env, MessageRow, ResolutionSource, Status } from '../types';
import { mapMessageRow } from './message-helpers';

const POLL_INTERVAL_MS = 3_000;
const KEEPALIVE_INTERVAL_MS = 15_000;
const MAX_DURATION_MS = 5 * 60 * 1_000;
// On connect, replay resolutions from this window so a client that reconnected
// after a decision was answered elsewhere can still dismiss a stale card.
const RECENT_RESOLUTION_WINDOW_MS = 10 * 60 * 1_000;

interface TrackedOption {
  expiresAt: string | null;
}

interface OptionResolution {
  id: string;
  status: 'replied' | 'expired';
  answer: string | null;
  source: ResolutionSource | null;
}

interface ReplyResolutionRow {
  body: string;
  channel: Channel | null;
  metadata: string | null;
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
    await replayRecentResolutions(writer, encoder, env, agentIds, new Date().toISOString());
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
    `SELECT messages.*, api_keys.name AS agent_name, sessions.label AS session_label, sessions.branch AS session_branch
     FROM messages
     LEFT JOIN api_keys ON api_keys.id = messages.agent_id
     LEFT JOIN sessions ON sessions.id = messages.session_id
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

/// Emits `resolved` for option messages resolved within the recent window, so a
/// client reconnecting after the resolution (its prior stream cycle ended, or it
/// was offline) can dismiss a stale card. The client ignores ids it isn't showing.
async function replayRecentResolutions(
  writer: WritableStreamDefaultWriter,
  encoder: TextEncoder,
  env: Env,
  agentIds: string[],
  now: string,
): Promise<void> {
  const placeholders = agentIds.map(() => '?').join(', ');
  const windowStart = new Date(Date.now() - RECENT_RESOLUTION_WINDOW_MS).toISOString();
  const rows = await env.DB.prepare(
    `SELECT id, expires_at
     FROM messages
     WHERE agent_id IN (${placeholders})
       AND direction = 'agent_to_boss'
       AND json_extract(metadata, '$.options') IS NOT NULL
       AND status IN ('replied', 'expired')
       AND updated_at > ?
     ORDER BY updated_at ASC`,
  ).bind(...agentIds, windowStart).all<{ id: string; expires_at: string | null }>();
  for (const row of rows.results ?? []) {
    const resolution = await resolveStatus(env, row.id, { expiresAt: row.expires_at ?? null }, now);
    await writeEvent(writer, encoder, 'resolved', resolution);
  }
}

async function resolveStatus(
  env: Env,
  messageId: string,
  tracked: TrackedOption,
  now: string,
): Promise<OptionResolution> {
  if (tracked.expiresAt && tracked.expiresAt <= now) {
    return { id: messageId, status: 'expired', answer: null, source: null };
  }
  const row = await env.DB.prepare('SELECT status FROM messages WHERE id = ?')
    .bind(messageId)
    .first<{ status: Status }>();
  if (row?.status === 'expired') {
    return { id: messageId, status: 'expired', answer: null, source: null };
  }
  const reply = await env.DB.prepare(
    'SELECT body, channel, metadata FROM messages WHERE reply_to = ? AND direction = ? ORDER BY created_at ASC LIMIT 1',
  ).bind(messageId, 'boss_to_agent').first<ReplyResolutionRow>();
  return {
    id: messageId,
    status: 'replied',
    answer: reply?.body ?? null,
    source: reply ? resolutionSource(reply) : null,
  };
}

function resolutionSource(reply: ReplyResolutionRow): ResolutionSource | null {
  const metadataSource = metadataResolutionSource(reply.metadata);
  if (metadataSource) return metadataSource;
  return reply.channel === 'api' || reply.channel === 'telegram' || reply.channel === 'discord'
    ? reply.channel
    : null;
}

function metadataResolutionSource(metadata: string | null): ResolutionSource | null {
  if (!metadata) return null;
  try {
    const parsed = JSON.parse(metadata) as Record<string, unknown>;
    const source = parsed['source'];
    return source === 'ios' || source === 'macos' || source === 'telegram' || source === 'discord' || source === 'api'
      ? source
      : null;
  } catch {
    return null;
  }
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
