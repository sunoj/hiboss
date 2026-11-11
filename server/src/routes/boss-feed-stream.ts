// Read-only SSE feed of all messages the boss can see, across every direction.
// Exports: streamBossFeed for the console's live message-feed view.
// Depends on D1, MessageRow mapping. Never mutates message status (a passive monitor). Each
// visibility branch seeks its own (column, updated_at) index; an OR of the two would scan.

import type { Env, MessageRow } from '../types';
import { mapMessageRow } from './message-helpers';
import { DEFAULT_BOSS_STREAM_POLL_INTERVAL_MS, getStreamPollIntervalMs } from './stream-config';

const KEEPALIVE_INTERVAL_MS = 15_000;
const MAX_DURATION_MS = 5 * 60 * 1_000;

export async function streamBossFeed(
  writer: WritableStreamDefaultWriter,
  encoder: TextEncoder,
  env: Env,
  agentIds: string[],
): Promise<void> {
  const startedAt = Date.now();
  let lastKeepalive = Date.now();
  let sinceTimestamp = new Date().toISOString().replace('T', ' ').slice(0, 19);
  const seenRows = new Map<string, string>();
  const pollIntervalMs = getStreamPollIntervalMs(env, DEFAULT_BOSS_STREAM_POLL_INTERVAL_MS);
  const placeholders = agentIds.map(() => '?').join(', ');
  const sql =
    `SELECT messages.*, api_keys.name AS agent_name
     FROM messages
     LEFT JOIN api_keys ON api_keys.id = messages.agent_id
     WHERE messages.rowid IN (
         SELECT rowid FROM messages WHERE agent_id IN (${placeholders}) AND updated_at >= ?
         UNION ALL
         SELECT rowid FROM messages WHERE target_agent_id IN (${placeholders}) AND updated_at >= ?)
     ORDER BY messages.updated_at ASC, messages.id ASC`;

  try {
    while (Date.now() - startedAt < MAX_DURATION_MS) {
      const rows = await env.DB.prepare(sql)
        .bind(...agentIds, sinceTimestamp, ...agentIds, sinceTimestamp)
        .all<MessageRow>();
      for (const row of rows.results ?? []) {
        const data = JSON.stringify(mapMessageRow(row));
        if (seenRows.get(row.id) === data) continue;
        await writer.write(encoder.encode(`event: message\ndata: ${data}\n\n`));
        seenRows.set(row.id, data);
        sinceTimestamp = row.updated_at;
      }
      if (Date.now() - lastKeepalive >= KEEPALIVE_INTERVAL_MS) {
        await writer.write(encoder.encode(': keepalive\n\n'));
        lastKeepalive = Date.now();
      }
      await delay(pollIntervalMs);
    }
  } catch {
    // The client disconnected; nothing to clean up (no shared state, no writes).
  } finally {
    try { await writer.close(); } catch { /* already closed */ }
  }
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
