// Integration tests for multi-client Boss option delivery and global withdrawal.
// Covers: fan-out to two streams, first-selection wins, and resolved SSE events.
// Depends on cloudflare:test, boss API routes, and shared database seeding.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { getTestAgentId, seedDatabase, seedBossToken } from '../test-helpers';

const TOKEN = 'hb_boss_option_stream_test_00000001';
const STREAM_URL = 'http://localhost/api/boss/stream?options=true';

beforeAll(async () => {
  await seedDatabase();
  await seedBossToken('Option Stream Boss', 'admin', TOKEN, 'option-stream-boss');
});

describe('Boss option stream lifecycle', () => {
  it('delivers one active option to two clients and withdraws it from both', async () => {
    const messageId = `multi-client-${Date.now()}`;
    await insertOptionMessage(messageId, 60);

    const first = await openOptionStream();
    const second = await openOptionStream();
    const firstMessage = await readEvent(first);
    expect(firstMessage).toContain(messageId);
    expect(firstMessage).toContain(`"session_label":"project-${messageId}"`);
    expect(firstMessage).toContain(`"session_branch":"branch-${messageId}"`);
    expect(await readEvent(second)).toContain(messageId);

    const reply = await replyTo(messageId, 'Approve', 'ios');
    expect(reply.status).toBe(201);
    const resolved = await readEvent(second, 5_000);
    expect(resolved).toContain(`"id":"${messageId}"`);
    expect(resolved).toContain('"status":"replied"');
    expect(resolved).toContain('"answer":"Approve"');
    expect(resolved).toContain('"source":"api"');

    await first.cancel();
    await second.cancel();
  });

  it('accepts only the first concurrent option selection', async () => {
    const messageId = `single-winner-${Date.now()}`;
    await insertOptionMessage(messageId, 60);

    const replies = await Promise.all([
      replyTo(messageId, 'Approve'),
      replyTo(messageId, 'Wait'),
    ]);

    expect(replies.map((reply) => reply.status).sort()).toEqual([201, 409]);
    const count = await env.DB.prepare(
      'SELECT COUNT(*) AS total FROM messages WHERE reply_to = ?',
    ).bind(messageId).first<{ total: number }>();
    expect(count?.total).toBe(1);
  });

  it('withdraws an option when its exact expiry passes', async () => {
    const messageId = `expires-${Date.now()}`;
    await insertOptionMessage(messageId, 1);
    const stream = await openOptionStream();

    expect(await readEvent(stream)).toContain(messageId);
    const resolved = await readEvent(stream, 5_000);
    expect(resolved).toContain('event: resolved');
    expect(resolved).toContain('"status":"expired"');
    expect(resolved).toContain('"answer":null');
    expect(resolved).toContain('"source":null');

    await stream.cancel();
  });

  it('lets a free-form reply claim an option message and withdraw it everywhere', async () => {
    const messageId = `free-text-${Date.now()}`;
    await insertOptionMessage(messageId, 60);
    const stream = await openOptionStream();
    expect(await readEvent(stream)).toContain(messageId);

    const reply = await replyTo(messageId, 'Roll back instead');
    expect(reply.status).toBe(201);

    expect(await readEvent(stream, 5_000)).toContain('event: resolved');
    const parent = await env.DB.prepare('SELECT status FROM messages WHERE id = ?')
      .bind(messageId)
      .first<{ status: string }>();
    expect(parent?.status).toBe('replied');
    const inserted = await env.DB.prepare('SELECT body FROM messages WHERE reply_to = ?')
      .bind(messageId)
      .first<{ body: string }>();
    expect(inserted?.body).toBe('Roll back instead');
    expect((await replyTo(messageId, 'Approve')).status).toBe(409);

    await stream.cancel();
  });

  it('ignores legacy option rows without an expiry', async () => {
    const messageId = `legacy-undated-${Date.now()}`;
    await env.DB.prepare(
      `INSERT INTO messages
        (id, agent_id, direction, mode, channel, body, status, priority, metadata)
       VALUES (?, ?, 'agent_to_boss', 'blocking', 'api', 'Legacy', 'sent', 'normal', ?)`,
    ).bind(messageId, getTestAgentId(), JSON.stringify({ options: ['Old'] })).run();
    const stream = await openOptionStream();

    await new Promise((resolve) => setTimeout(resolve, 50));
    const row = await env.DB.prepare('SELECT status FROM messages WHERE id = ?')
      .bind(messageId)
      .first<{ status: string }>();
    expect(row?.status).toBe('sent');
    expect((await replyTo(messageId, 'Old')).status).toBe(409);

    await stream.cancel();
  });
});

async function insertOptionMessage(messageId: string, expiresInSeconds: number): Promise<void> {
  const expiresAt = new Date(Date.now() + expiresInSeconds * 1_000).toISOString();
  const sessionId = `session-${messageId}`;
  await env.DB.prepare(
    'INSERT OR REPLACE INTO sessions (id, agent_id, label, branch) VALUES (?, ?, ?, ?)',
  ).bind(sessionId, getTestAgentId(), `project-${messageId}`, `branch-${messageId}`).run();
  await env.DB.prepare(
    `INSERT INTO messages
      (id, agent_id, direction, mode, channel, body, status, priority, metadata, expires_at, session_id)
     VALUES (?, ?, 'agent_to_boss', 'blocking', 'api', 'Choose', 'sent', 'normal', ?, ?, ?)`,
  ).bind(messageId, getTestAgentId(), JSON.stringify({ options: ['Approve', 'Wait'] }), expiresAt, sessionId).run();
}

async function openOptionStream(): Promise<ReadableStreamDefaultReader<Uint8Array>> {
  const response = await SELF.fetch(STREAM_URL, { headers: headers() });
  expect(response.status).toBe(200);
  const reader = response.body?.getReader();
  if (!reader) throw new Error('option stream has no reader');
  return reader;
}

async function readEvent(
  reader: ReadableStreamDefaultReader<Uint8Array>,
  timeoutMs = 1_000,
): Promise<string> {
  const result = await Promise.race([
    reader.read(),
    new Promise<never>((_, reject) => {
      setTimeout(() => reject(new Error('timed out waiting for SSE event')), timeoutMs);
    }),
  ]);
  return new TextDecoder().decode(result.value);
}

function replyTo(messageId: string, body: string, source?: string): Promise<Response> {
  return SELF.fetch(`http://localhost/api/boss/messages/${messageId}/reply`, {
    method: 'POST',
    headers: headers(),
    body: JSON.stringify(source ? { body, source } : { body }),
  });
}

function headers(): Record<string, string> {
  return { Authorization: `Bearer ${TOKEN}`, 'Content-Type': 'application/json' };
}
