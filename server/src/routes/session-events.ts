// Session event history and resumable SSE endpoints.
// Exports sessionEventsRouter mounted at /api/sessions.
// Depends on Hono, dual auth, D1, session event parsing, and stream timing config.

import { Hono } from 'hono';
import type { Context } from 'hono';
import type { Env } from '../types';
import { dualAuth, getAgentId, getBossId, getBossRole, isBossAuth } from '../middleware/auth';
import { getAccessibleAgentIds } from './boss-api';
import { DEFAULT_AGENT_STREAM_POLL_INTERVAL_MS, getStreamPollIntervalMs } from './stream-config';

const DEFAULT_LIMIT = 100;
const MAX_LIMIT = 500;
const KEEPALIVE_INTERVAL_MS = 15000;
const MAX_DURATION_MS = 5 * 60 * 1000;

interface SessionEventRow {
  id: string;
  session_id: string;
  sequence: number;
  kind: string;
  direction: string | null;
  actor_agent_id: string | null;
  actor_name: string | null;
  target_agent_id: string | null;
  message_id: string | null;
  source: string | null;
  payload: string | null;
  raw: string | null;
  created_at: string;
}

const routes = new Hono<{ Bindings: Env }>({});
routes.use('*', dualAuth);

routes.get('/:id/events', async (c) => {
  const sessionId = await visibleSessionId(c);
  if (!sessionId) return c.text('not found', 404);
  const after = parseCursor(c.req.query('after'));
  if (after === null && c.req.query('after') !== undefined) return c.text('after must be an integer', 400);
  const limit = parseLimit(c.req.query('limit'));
  const first = await c.env.DB.prepare('SELECT MIN(sequence) AS sequence FROM session_events WHERE session_id = ?').bind(sessionId).first<{ sequence: number | null }>();
  if (after !== null && first?.sequence !== null && first?.sequence !== undefined && after < first.sequence - 1) {
    return c.json({ events: [], resync: true });
  }
  const rows = await fetchEvents(c.env, sessionId, after ?? -1, limit);
  const events = rows.map(mapEvent);
  return c.json({ events, next_after: events.at(-1)?.sequence ?? null, resync: false });
});

routes.get('/:id/stream', async (c) => {
  const sessionId = await visibleSessionId(c);
  if (!sessionId) return c.text('not found', 404);
  const queryCursor = parseCursor(c.req.query('after'));
  const headerCursor = parseCursor(c.req.header('Last-Event-ID'));
  const after = queryCursor ?? headerCursor ?? -1;
  if (queryCursor === null && c.req.query('after') !== undefined) return c.text('after must be an integer', 400);
  if (queryCursor === null && headerCursor === null && c.req.header('Last-Event-ID')) return c.text('Last-Event-ID must be an integer', 400);
  const { readable, writable } = new TransformStream();
  c.executionCtx.waitUntil(streamLoop(writable.getWriter(), new TextEncoder(), c.env, sessionId, after));
  return new Response(readable, { headers: { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', 'Connection': 'keep-alive' } });
});

export const sessionEventsRouter = routes;

async function visibleSessionId(c: Context<{ Bindings: Env }>): Promise<string | null> {
  const requested = c.req.param('id');
  if (!isBossAuth(c)) {
    const row = await c.env.DB.prepare('SELECT id FROM sessions WHERE id = ? AND agent_id = ?').bind(requested, getAgentId(c)).first<{ id: string }>();
    return row?.id ?? null;
  }
  const agentIds = await getAccessibleAgentIds(c.env, getBossId(c), getBossRole(c));
  if (agentIds.length === 0) return null;
  const placeholders = agentIds.map(() => '?').join(', ');
  const row = await c.env.DB.prepare(`SELECT id FROM sessions WHERE id = ? AND agent_id IN (${placeholders})`).bind(requested, ...agentIds).first<{ id: string }>();
  return row?.id ?? null;
}

async function fetchEvents(env: Env, sessionId: string, after: number, limit: number): Promise<SessionEventRow[]> {
  const rows = await env.DB.prepare(
    `SELECT session_events.*, api_keys.name AS actor_name
     FROM session_events LEFT JOIN api_keys ON api_keys.id = session_events.actor_agent_id
     WHERE session_events.session_id = ? AND session_events.sequence > ?
     ORDER BY session_events.sequence ASC LIMIT ?`,
  ).bind(sessionId, after, limit).all<SessionEventRow>();
  return rows.results ?? [];
}

async function streamLoop(
  writer: WritableStreamDefaultWriter,
  encoder: TextEncoder,
  env: Env,
  sessionId: string,
  after: number,
): Promise<void> {
  const startedAt = Date.now();
  let cursor = after;
  let lastKeepalive = Date.now();
  const pollIntervalMs = getStreamPollIntervalMs(env, DEFAULT_AGENT_STREAM_POLL_INTERVAL_MS);
  try {
    while (Date.now() - startedAt < MAX_DURATION_MS) {
      const first = await env.DB.prepare('SELECT MIN(sequence) AS sequence FROM session_events WHERE session_id = ?').bind(sessionId).first<{ sequence: number | null }>();
      if (cursor >= 0 && first?.sequence !== null && first?.sequence !== undefined && cursor < first.sequence - 1) {
        await writer.write(encoder.encode('event: resync\ndata: {"resync":true}\n\n'));
        cursor = (await env.DB.prepare('SELECT MAX(sequence) AS sequence FROM session_events WHERE session_id = ?').bind(sessionId).first<{ sequence: number | null }>())?.sequence ?? cursor;
      }
      const events = await fetchEvents(env, sessionId, cursor, MAX_LIMIT);
      for (const event of events) {
        await writer.write(encoder.encode(`id: ${event.sequence}\nevent: session_event\ndata: ${JSON.stringify(mapEvent(event))}\n\n`));
        cursor = event.sequence;
      }
      if (Date.now() - lastKeepalive >= KEEPALIVE_INTERVAL_MS) {
        await writer.write(encoder.encode(': keepalive\n\n'));
        lastKeepalive = Date.now();
      }
      await delay(pollIntervalMs);
    }
  } catch {
    // Client disconnects terminate the stream loop.
  } finally {
    try { await writer.close(); } catch { /* already closed */ }
  }
}

function mapEvent(row: SessionEventRow): Record<string, unknown> {
  return {
    id: row.id,
    session_id: row.session_id,
    sequence: row.sequence,
    kind: row.kind,
    direction: row.direction,
    actor_agent_id: row.actor_agent_id,
    actor_name: row.actor_name,
    target_agent_id: row.target_agent_id,
    message_id: row.message_id,
    source: parseJson(row.source),
    payload: parseJson(row.payload),
    raw: parseJson(row.raw),
    created_at: row.created_at,
  };
}

function parseJson(value: string | null): unknown {
  if (value === null) return null;
  try { return JSON.parse(value) as unknown; } catch { return value; }
}

function parseCursor(value: string | undefined): number | null {
  if (value === undefined || value.trim() === '') return null;
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed >= 0 ? parsed : null;
}

function parseLimit(value: string | undefined): number {
  const parsed = Number(value ?? DEFAULT_LIMIT);
  if (!Number.isSafeInteger(parsed) || parsed < 1) return DEFAULT_LIMIT;
  return Math.min(parsed, MAX_LIMIT);
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
