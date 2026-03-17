// SSE streaming endpoint for real-time message delivery to agents.
// Exports GET /stream that pushes boss_to_agent and agent_to_agent messages via SSE.
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
  const sessionId = c.req.query('session') || undefined;
  const { readable, writable } = new TransformStream();
  const writer = writable.getWriter();
  const encoder = new TextEncoder();

  c.executionCtx.waitUntil(streamLoop(writer, encoder, c.env, agentId, sessionId));

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
  sessionId?: string,
): Promise<void> {
  const start = Date.now();
  let lastCheck = new Date().toISOString().replace('T', ' ').slice(0, 19);
  let lastKeepalive = Date.now();
  const seenMessageIds = new Set<string>();

  // Build the WHERE clause based on whether session filtering is active
  const { sql, buildBinds } = buildStreamQuery(agentId, sessionId);

  try {
    while (Date.now() - start < MAX_DURATION_MS) {
      const rows = await env.DB
        .prepare(sql)
        .bind(...buildBinds(lastCheck))
        .all<MessageRow>();

      pruneSeenMessageIds(seenMessageIds, rows.results ?? [], lastCheck);
      for (const row of rows.results ?? []) {
        if (seenMessageIds.has(row.id)) continue;
        const data = JSON.stringify({ ...row, metadata: safeJson(row.metadata) });
        await writer.write(encoder.encode(`event: message\ndata: ${data}\n\n`));
        await env.DB
          .prepare("UPDATE messages SET status = 'delivered', updated_at = datetime('now') WHERE id = ?")
          .bind(row.id)
          .run();
        seenMessageIds.add(row.id);
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

/** Build SQL and bind factory for the stream query. Includes boss and a2a messages. */
function buildStreamQuery(agentId: string, sessionId?: string) {
  // Boss messages: agent_id = ? AND direction = 'boss_to_agent'
  // A2A messages: target_agent_id = ? AND direction = 'agent_to_agent'
  //   If sessionId: also match target_session_id = ? (or NULL for agent-wide a2a)
  const baseCols = 'SELECT messages.*, api_keys.name AS agent_name FROM messages LEFT JOIN api_keys ON api_keys.id = messages.agent_id';

  if (sessionId) {
    // Session-scoped: boss messages + a2a targeting this agent (no session) + a2a targeting this session
    const where = `WHERE messages.status = 'sent' AND messages.created_at >= ? AND (
      (messages.agent_id = ? AND messages.direction = 'boss_to_agent')
      OR (messages.target_agent_id = ? AND messages.direction = 'agent_to_agent' AND messages.target_session_id IS NULL)
      OR (messages.target_session_id = ? AND messages.direction = 'agent_to_agent')
    ) ORDER BY messages.created_at ASC`;
    return {
      sql: `${baseCols} ${where}`,
      buildBinds: (lastCheck: string) => [lastCheck, agentId, agentId, sessionId],
    };
  }

  // Agent-wide: boss messages + all a2a targeting this agent
  const where = `WHERE messages.status = 'sent' AND messages.created_at >= ? AND (
    (messages.agent_id = ? AND messages.direction = 'boss_to_agent')
    OR (messages.target_agent_id = ? AND messages.direction = 'agent_to_agent')
  ) ORDER BY messages.created_at ASC`;
  return {
    sql: `${baseCols} ${where}`,
    buildBinds: (lastCheck: string) => [lastCheck, agentId, agentId],
  };
}

function safeJson(value: string | null): Record<string, unknown> | null {
  if (!value) return null;
  try { return JSON.parse(value); } catch { return null; }
}

export function pruneSeenMessageIds(seenMessageIds: Set<string>, rows: MessageRow[], lastCheck: string): void {
  if (rows.length === 0) {
    seenMessageIds.clear();
    return;
  }
  const floor = rows[0]?.created_at ?? lastCheck;
  if (floor > lastCheck) {
    seenMessageIds.clear();
  }
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
