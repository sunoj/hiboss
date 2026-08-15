// Integration tests for session event history, atomic appends, and resumable SSE.
// Covers concurrent sequence allocation, cursor replay, resync, visibility, and backfill ordering.
// Depends on cloudflare:test, the Hono app, and shared database/auth helpers.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { authHeaders, getTestAgentId, seedDatabase } from '../test-helpers';
import { handleScheduled } from '../scheduled';
import type { Env } from '../types';

interface EventResponse {
  sequence: number;
  message_id: string | null;
  session_id: string;
  kind: string;
  raw: Record<string, unknown> | null;
}

interface HistoryResponse {
  events: EventResponse[];
  next_after?: number | null;
  resync?: boolean;
}

const prefix = `session-events-${Date.now()}`;

beforeAll(async () => {
  await seedDatabase();
});

async function createSession(id: string): Promise<void> {
  await env.DB.prepare(
    "INSERT OR IGNORE INTO sessions (id, agent_id, label, status) VALUES (?, ?, ?, 'working')",
  ).bind(id, getTestAgentId(), id).run();
}

async function sendMessage(sessionId: string, body: string): Promise<string> {
  const response = await SELF.fetch('https://test.local/api/messages', {
    method: 'POST',
    headers: authHeaders(),
    body: JSON.stringify({ body, session_id: sessionId }),
  });
  expect(response.status).toBe(201);
  const data = await response.json() as { id: string };
  return data.id;
}

async function history(sessionId: string, query = ''): Promise<HistoryResponse> {
  const response = await SELF.fetch(`https://test.local/api/sessions/${sessionId}/events${query}`, { headers: authHeaders() });
  expect(response.status).toBe(200);
  return await response.json() as HistoryResponse;
}

describe('session event history', () => {
  it('appends an agent message and exposes its lossless event projection', async () => {
    const sessionId = `${prefix}-message`;
    await createSession(sessionId);
    const messageId = await sendMessage(sessionId, 'event body');
    const data = await history(sessionId);
    expect(data.events).toHaveLength(1);
    expect(data.events[0]).toMatchObject({ session_id: sessionId, sequence: 1, kind: 'message', message_id: messageId });
    expect(data.events[0]?.raw?.['body']).toBe('event body');
    expect(data.events[0]?.raw?.['session_id']).toBe(sessionId);
  });

  it('keeps sequences unique and contiguous under concurrent appends', async () => {
    const sessionId = `${prefix}-concurrent`;
    await createSession(sessionId);
    await Promise.all(Array.from({ length: 12 }, (_, index) => sendMessage(sessionId, `body-${index}`)));
    const data = await history(sessionId);
    expect(data.events.map((event) => event.sequence)).toEqual(Array.from({ length: 12 }, (_, i) => i + 1));
  });

  it('resumes after a cursor without a gap or duplicate', async () => {
    const sessionId = `${prefix}-resume`;
    await createSession(sessionId);
    await Promise.all([sendMessage(sessionId, 'one'), sendMessage(sessionId, 'two'), sendMessage(sessionId, 'three')]);
    const first = await history(sessionId, '?limit=1');
    const cursor = first.events[0]?.sequence;
    const resumed = await history(sessionId, `?after=${cursor}`);
    expect(resumed.events.map((event) => event.sequence)).toEqual([2, 3]);
    expect(new Set(resumed.events.map((event) => event.message_id)).size).toBe(2);
  });

  it('records agent-to-agent sends and agent replies in the owning session', async () => {
    const sessionId = `${prefix}-agent-reply`;
    const targetSessionId = `${prefix}-agent-target`;
    await createSession(sessionId);
    await createSession(targetSessionId);
    const send = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'peer request', session_id: sessionId, to: targetSessionId }),
    });
    expect(send.status).toBe(201);
    const sent = await send.json() as { id: string };
    const reply = await SELF.fetch(`https://test.local/api/messages/${sent.id}/reply`, {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'peer reply' }),
    });
    expect(reply.status).toBe(201);
    const data = await history(sessionId);
    expect(data.events.map((event) => event.message_id)).toEqual([sent.id, (await reply.json() as { id: string }).id]);
  });

  it('returns resync when the cursor predates retained history', async () => {
    const sessionId = `${prefix}-resync`;
    await createSession(sessionId);
    await sendMessage(sessionId, 'retained');
    await sendMessage(sessionId, 'retained too');
    await env.DB.prepare('DELETE FROM session_events WHERE session_id = ? AND sequence = 1').bind(sessionId).run();
    const data = await history(sessionId, '?after=0');
    expect(data).toEqual({ events: [], resync: true });
  });

  it('streams replayed events with sequence IDs', async () => {
    const sessionId = `${prefix}-stream`;
    await createSession(sessionId);
    await sendMessage(sessionId, 'stream body');
    const response = await SELF.fetch(`https://test.local/api/sessions/${sessionId}/stream?after=0`, { headers: authHeaders() });
    expect(response.status).toBe(200);
    const reader = response.body?.getReader();
    if (!reader) throw new Error('stream body missing');
    const first = await reader.read();
    const text = new TextDecoder().decode(first.value);
    expect(text).toContain('id: 1');
    expect(text).toContain('event: session_event');
    await reader.cancel();
  });
});

describe('session event migration backfill', () => {
  it('backfills pre-existing messages in created_at/id order', async () => {
    const sessionId = `${prefix}-backfill`;
    await createSession(sessionId);
    const messages = [
      ['backfill-b', '2026-01-01T00:00:00Z'],
      ['backfill-a', '2026-01-01T00:00:00Z'],
      ['backfill-c', '2026-01-01T00:00:01Z'],
    ];
    for (const [id, createdAt] of messages) {
      await env.DB.prepare(
        "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, session_id, created_at, updated_at) VALUES (?, ?, 'agent_to_boss', 'async', 'api', ?, 'sent', 'normal', ?, ?, ?)",
      ).bind(id, getTestAgentId(), id, sessionId, createdAt, createdAt).run();
    }
    await env.DB.prepare(`
      WITH ordered_messages AS (
        SELECT messages.*, ROW_NUMBER() OVER (PARTITION BY session_id ORDER BY created_at, id) AS event_sequence
        FROM messages WHERE session_id = ?
      )
      INSERT INTO session_events (session_id, sequence, kind, direction, actor_agent_id, message_id, source, payload, raw)
      SELECT session_id, event_sequence, 'message', direction, agent_id, id,
        json_object('record_type', 'message'), json_object('body', body), json_object('id', id, 'body', body)
      FROM ordered_messages
    `).bind(sessionId).run();
    const rows = await env.DB.prepare('SELECT message_id, sequence FROM session_events WHERE session_id = ? ORDER BY sequence').bind(sessionId).all<{ message_id: string; sequence: number }>();
    expect(rows.results).toEqual([
      { message_id: 'backfill-a', sequence: 1 },
      { message_id: 'backfill-b', sequence: 2 },
      { message_id: 'backfill-c', sequence: 3 },
    ]);
  });

  it('appends the scheduled expiry sweep default resolution atomically', async () => {
    const sessionId = `${prefix}-scheduled`;
    await createSession(sessionId);
    const messageId = `${prefix}-scheduled-message`;
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, metadata, session_id, expires_at) VALUES (?, ?, 'agent_to_boss', 'blocking', 'api', 'Choose scheduled', 'sent', 'normal', ?, ?, '2020-01-01T00:00:00Z')",
    ).bind(messageId, getTestAgentId(), JSON.stringify({ options: ['yes'], default_option: 'yes' }), sessionId).run();
    await handleScheduled(env as Env);
    const reply = await env.DB.prepare('SELECT id FROM messages WHERE reply_to = ?').bind(messageId).first<{ id: string }>();
    const event = await env.DB.prepare('SELECT session_id, message_id FROM session_events WHERE message_id = ?').bind(reply?.id).first<{ session_id: string; message_id: string }>();
    expect(event).toEqual({ session_id: sessionId, message_id: reply?.id });
  });
});
