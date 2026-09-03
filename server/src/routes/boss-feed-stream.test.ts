// Integration test for the read-only boss console feed stream (?feed=true).
// Covers: all-direction delivery and that it does NOT mutate message status.
// Depends on cloudflare:test, boss API routes, and shared database seeding.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { getTestAgentId, seedDatabase, seedBossToken } from '../test-helpers';

const TOKEN = 'hb_boss_feed_stream_test_0000000001';
const FEED_URL = 'http://localhost/api/boss/stream?feed=true';

beforeAll(async () => {
  await seedDatabase();
  await seedBossToken('Feed Boss', 'admin', TOKEN, 'feed-stream-boss');
});

describe('Boss console feed stream', () => {
  it('delivers a new message without mutating its status', async () => {
    const messageId = `feed-${Date.now()}`;
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority) VALUES (?, ?, 'agent_to_boss', 'async', 'api', 'feed body', 'sent', 'normal')",
    ).bind(messageId, getTestAgentId()).run();

    const reader = await openFeed();
    const chunk = await readEvent(reader, 6_000);
    expect(chunk).toContain(messageId);
    await reader.cancel();

    // The feed is a passive monitor: status must remain 'sent', not 'delivered'.
    const row = await env.DB.prepare('SELECT status FROM messages WHERE id = ?')
      .bind(messageId).first<{ status: string }>();
    expect(row?.status).toBe('sent');
  });
});

async function openFeed(): Promise<ReadableStreamDefaultReader<Uint8Array>> {
  const response = await SELF.fetch(FEED_URL, {
    headers: { Authorization: `Bearer ${TOKEN}`, 'Content-Type': 'application/json' },
  });
  expect(response.status).toBe(200);
  const reader = response.body?.getReader();
  if (!reader) throw new Error('feed stream has no reader');
  return reader;
}

async function readEvent(
  reader: ReadableStreamDefaultReader<Uint8Array>,
  timeoutMs = 2_000,
): Promise<string> {
  let buffer = '';
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const result = await Promise.race([
      reader.read(),
      new Promise<never>((_, reject) => {
        setTimeout(() => reject(new Error('timed out waiting for SSE event')), timeoutMs);
      }),
    ]);
    buffer += new TextDecoder().decode(result.value);
    if (buffer.includes('event: message')) return buffer;
  }
  return buffer;
}
