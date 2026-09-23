// Boss SSE delivery extracted without changing stream selection or polling.
// Exports bossStreamRouter; depends on D1, stream helpers, and shared boss access.
import { Hono } from 'hono';
import type { Env, MessageRow } from '../types';
import { getBossId, getBossRole } from '../middleware/auth';
import { authorizedStreamWriter } from '../middleware/authorized-stream';
import { getAccessibleAgentIds } from './boss-api-access';
import { mapMessageRow } from './message-helpers';
import { streamBossOptions } from './boss-option-stream';
import { streamBossFeed } from './boss-feed-stream';
import { streamBossRequiredInputs } from './boss-required-input-stream';
const routes = new Hono<{ Bindings: Env }>();

/** GET /api/boss/stream — SSE stream of new agent messages for the boss */
routes.get('/stream', async (c) => {
  const bossId = getBossId(c);
  const agentIds = await getAccessibleAgentIds(c.env, bossId, getBossRole(c));
  if (agentIds.length === 0) return c.text('no agents', 403);
  const { readable, writable } = new TransformStream();
  const writer = authorizedStreamWriter(c, writable, async () => {
    const current = new Set(await getAccessibleAgentIds(c.env, bossId, getBossRole(c)));
    return agentIds.every(id => current.has(id));
  });
  const encoder = new TextEncoder();

  const stream = c.req.query('options') === 'true'
    ? streamBossOptions(writer, encoder, c.env, agentIds)
    : c.req.query('inputs') === 'true'
      ? streamBossRequiredInputs(writer, encoder, c.env, agentIds)
      : c.req.query('feed') === 'true'
        ? streamBossFeed(writer, encoder, c.env, agentIds)
        : bossStreamLoop(writer, encoder, c.env, bossId, agentIds);
  c.executionCtx.waitUntil(stream);

  return new Response(readable, {
    headers: { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', 'Connection': 'keep-alive' },
  });
});

const BOSS_POLL_MS = 3000;
const BOSS_KEEPALIVE_MS = 15000;
const BOSS_MAX_DURATION_MS = 5 * 60 * 1000;

async function bossStreamLoop(
  writer: WritableStreamDefaultWriter, encoder: TextEncoder,
  env: Env, bossId: string, agentIds: string[],
): Promise<void> {
  const start = Date.now();
  let lastCheck = new Date().toISOString().replace('T', ' ').slice(0, 19);
  let lastKeepalive = Date.now();
  const seenIds = new Set<string>();
  const placeholders = agentIds.map(() => '?').join(', ');
  const sql = `SELECT messages.*, api_keys.name AS agent_name FROM messages LEFT JOIN api_keys ON api_keys.id = messages.agent_id WHERE agent_id IN (${placeholders}) AND direction = 'agent_to_boss' AND status = 'sent' AND messages.created_at >= ? ORDER BY messages.created_at ASC`;

  try {
    while (Date.now() - start < BOSS_MAX_DURATION_MS) {
      const rows = await env.DB.prepare(sql).bind(...agentIds, lastCheck).all<MessageRow>();
      for (const row of rows.results ?? []) {
        if (seenIds.has(row.id)) continue;
        const data = JSON.stringify(mapMessageRow(row));
        await writer.write(encoder.encode(`event: message\ndata: ${data}\n\n`));
        await env.DB.prepare("UPDATE messages SET status = 'delivered', updated_at = datetime('now') WHERE id = ?").bind(row.id).run();
        seenIds.add(row.id);
        lastCheck = row.created_at;
      }
      if (Date.now() - lastKeepalive >= BOSS_KEEPALIVE_MS) {
        await writer.write(encoder.encode(': keepalive\n\n'));
        lastKeepalive = Date.now();
      }
      await new Promise((r) => setTimeout(r, BOSS_POLL_MS));
    }
  } catch { /* client disconnected */ } finally {
    try { await writer.close(); } catch { /* already closed */ }
  }
}

export const bossStreamRouter = routes;
