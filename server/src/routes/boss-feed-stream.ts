// Read-only SSE feed of all messages the boss can see, across every direction.
// Exports: streamBossFeed for the console's live message-feed view.
// Depends on D1, MessageRow mapping. Unlike the option/agent streams it never
// mutates message status — it is a passive monitor, not a delivery channel.

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
  const seenIds = new Set<string>();
  const pollIntervalMs = getStreamPollIntervalMs(env, DEFAULT_BOSS_STREAM_POLL_INTERVAL_MS);
  const placeholders = agentIds.map(() => '?').join(', ');
  const sql =
    `SELECT messages.*, api_keys.name AS agent_name
     FROM messages
     LEFT JOIN api_keys ON api_keys.id = messages.agent_id
     WHERE (messages.agent_id IN (${placeholders}) OR messages.target_agent_id IN (${placeholders}))
       AND messages.created_at >= ?
     ORDER BY messages.created_at ASC`;

  try {
    while (Date.now() - startedAt < MAX_DURATION_MS) {
      const rows = await env.DB.prepare(sql)
        .bind(...agentIds, ...agentIds, sinceTimestamp)
        .all<MessageRow>();
      for (const row of rows.results ?? []) {
        if (seenIds.has(row.id)) continue;
        const data = JSON.stringify(mapMessageRow(row));
        await writer.write(encoder.encode(`event: message\ndata: ${data}\n\n`));
        seenIds.add(row.id);
        sinceTimestamp = row.created_at;
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
