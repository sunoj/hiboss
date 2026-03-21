// Periodic sweep that expires options messages past their expires_at deadline.
// Exports the scheduled handler for Cloudflare Worker cron triggers.
// Depends on Env type and expireMessageOptions from message-options.

import type { Env, MessageRow } from './types';
import { expireMessageOptions } from './routes/message-options';

const BATCH_SIZE = 50;

export async function handleScheduled(env: Env): Promise<void> {
  const now = new Date().toISOString();
  const rows = await env.DB
    .prepare(
      `SELECT * FROM messages WHERE expires_at IS NOT NULL AND expires_at < ? AND status IN ('sent', 'delivered', 'read') AND json_extract(metadata, '$.options') IS NOT NULL LIMIT ?`
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
