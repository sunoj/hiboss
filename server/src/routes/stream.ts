// SSE streaming endpoint for real-time message delivery to agents.
// Exports GET /stream that pushes new boss_to_agent messages via Server-Sent Events.
// Depends on Hono, D1, auth middleware, and Cloudflare Workers streaming primitives.

import { Hono } from 'hono';
import type { Env, MessageRow } from '../types';
import { apiAuth, getAgentId } from '../middleware/auth';

const POLL_INTERVAL_MS = 2000;
const KEEPALIVE_INTERVAL_MS = 15000;
const MAX_DURATION_MS = 5 * 60 * 1000;

const routes = new Hono<{ Bindings: Env }>({});
routes.use('*', apiAuth);

routes.get('/stream', async (c) => {
  const agentId = getAgentId(c);
  const { readable, writable } = new TransformStream();
  const writer = writable.getWriter();
  const encoder = new TextEncoder();

  c.executionCtx.waitUntil(streamLoop(writer, encoder, c.env, agentId));

  return new Response(readable, {
    headers: {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
    },
  });
});

export const streamRouter = routes;

async function streamLoop(
  writer: WritableStreamDefaultWriter,
  encoder: TextEncoder,
  env: Env,
  agentId: string,
): Promise<void> {
  const start = Date.now();
  let lastCheck = new Date().toISOString().replace('T', ' ').slice(0, 19);
  let lastKeepalive = Date.now();

  try {
    while (Date.now() - start < MAX_DURATION_MS) {
      const rows = await env.DB
        .prepare(
          "SELECT messages.*, api_keys.name AS agent_name FROM messages LEFT JOIN api_keys ON api_keys.id = messages.agent_id WHERE messages.agent_id = ? AND messages.direction = 'boss_to_agent' AND messages.status = 'sent' AND messages.created_at > ? ORDER BY messages.created_at ASC"
        )
        .bind(agentId, lastCheck)
        .all<MessageRow>();

      for (const row of rows.results ?? []) {
        const data = JSON.stringify({ ...row, metadata: safeJson(row.metadata) });
        await writer.write(encoder.encode(`event: message\ndata: ${data}\n\n`));
        await env.DB
          .prepare("UPDATE messages SET status = 'delivered', updated_at = datetime('now') WHERE id = ?")
          .bind(row.id)
          .run();
        lastCheck = row.created_at;
      }

      if (Date.now() - lastKeepalive >= KEEPALIVE_INTERVAL_MS) {
        await writer.write(encoder.encode(': keepalive\n\n'));
        lastKeepalive = Date.now();
      }

      await delay(POLL_INTERVAL_MS);
    }
  } catch {
    // Client disconnected or write failed — close gracefully.
  } finally {
    try { await writer.close(); } catch { /* already closed */ }
  }
}

function safeJson(value: string | null): Record<string, unknown> | null {
  if (!value) return null;
  try { return JSON.parse(value); } catch { return null; }
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
