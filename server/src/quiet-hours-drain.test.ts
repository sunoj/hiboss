// Quiet-hours queue drain: a queued send gets the same boss notification as an immediate one,
// and an ask that was answered, expired or timed out while queued is never sent.
// Depends on the Worker (SELF) send route, seeded D1, and handleScheduled.

import { testRequest } from './test-request';
import { env } from 'cloudflare:test';
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { seedDatabase } from './test-helpers';
import { hashApiKey } from './middleware/auth';
import { handleScheduled } from './scheduled';

const AGENT = 'quiet-drain-agent';
const KEY = 'hb_quiet_drain_agent_key_0001';
const BOSS_AGENT = 'quiet-drain-boss-agent';
const CALLBACK = 'https://boss-agent.test/callback';
const utcTime = (offsetMinutes: number): string => new Date(Date.now() + offsetMinutes * 60_000).toISOString().slice(11, 16);

beforeAll(async () => {
  await seedDatabase();
  await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind(AGENT, AGENT, await hashApiKey(KEY)).run();
  await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash, callback_url) VALUES (?, ?, ?, ?)')
    .bind(BOSS_AGENT, BOSS_AGENT, await hashApiKey(`${KEY}-boss`), CALLBACK).run();
  await env.DB.prepare("INSERT OR REPLACE INTO bosses (id, name, role, agent_id, preferences) VALUES (?, ?, 'manager', ?, ?)")
    .bind('quiet-drain-boss', 'Quiet Drain Boss', BOSS_AGENT,
      JSON.stringify({ quiet_hours_start: utcTime(-1), quiet_hours_end: utcTime(1), timezone: 'UTC' })).run();
  await env.DB.prepare('INSERT OR REPLACE INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
    .bind('quiet-drain-boss', AGENT).run();
});

beforeEach(async () => {
  await env.DB.prepare("INSERT OR REPLACE INTO channel_configs (id, agent_id, channel, config, enabled) VALUES (?, ?, 'api', '{}', 1)")
    .bind(`cfg-${AGENT}`, AGENT).run();
});

afterEach(() => {
  vi.unstubAllGlobals();
});

async function queuedSend(body: Record<string, unknown>): Promise<string> {
  const res = await testRequest('POST', 'https://test.local/api/messages',
    { Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' }, body);
  expect(res.status).toBe(201);
  const { id } = await res.json() as { id: string };
  const due = await env.DB.prepare("UPDATE delivery_queue SET scheduled_at = '2000-01-01T00:00:00.000Z' WHERE message_id = ? RETURNING id")
    .bind(id).first();
  expect(due).not.toBeNull();
  return id;
}

async function drain(): Promise<string[]> {
  const fetchMock = vi.fn().mockResolvedValue(new Response(null, { status: 204 }));
  vi.stubGlobal('fetch', fetchMock);
  await handleScheduled(env);
  vi.unstubAllGlobals();
  return fetchMock.mock.calls
    .filter(([url]) => String(url) === CALLBACK)
    .map(([, init]) => (JSON.parse(String((init as RequestInit).body)) as { id: string }).id);
}

async function queueRow(messageId: string): Promise<{ status: string; error: string | null } | null> {
  return env.DB.prepare('SELECT status, error FROM delivery_queue WHERE message_id = ?')
    .bind(messageId).first<{ status: string; error: string | null }>();
}

describe('quiet-hours drain', () => {
  it('holds and drains boss notifications without legacy channels', async () => {
    await env.DB.prepare('DELETE FROM channel_configs WHERE agent_id = ?').bind(AGENT).run();
    const id = await queuedSend({ body: 'native-only quiet hours' });
    const notified = await drain();
    expect((await queueRow(id))?.status).toBe('delivered');
    expect(notified).toContain(id);
  });

  it('notifies boss agents when a queued message is finally delivered', async () => {
    const id = await queuedSend({ body: 'quiet-drain:later' });
    const notified = await drain();
    expect((await queueRow(id))?.status).toBe('delivered');
    expect(notified).toContain(id);
  });

  it('skips an ask that was answered while it waited in the queue', async () => {
    const id = await queuedSend({ body: 'quiet-drain:answered?', options: ['Yes', 'No'] });
    await env.DB.prepare("UPDATE messages SET status = 'replied' WHERE id = ?").bind(id).run();
    const notified = await drain();
    expect(await queueRow(id)).toMatchObject({ status: 'failed', error: 'ask closed before delivery' });
    expect(notified).not.toContain(id);
    expect((await env.DB.prepare('SELECT status FROM messages WHERE id = ?').bind(id).first<{ status: string }>())?.status)
      .toBe('replied');
  });

  it('skips an ask whose deadline passed while it waited in the queue', async () => {
    const id = await queuedSend({ body: 'quiet-drain:elapsed?', mode: 'blocking', timeout: 60, options: ['Yes', 'No'] });
    await env.DB.prepare("UPDATE messages SET expires_at = '2000-01-01T00:00:00.000Z' WHERE id = ?").bind(id).run();
    const notified = await drain();
    expect(await queueRow(id)).toMatchObject({ status: 'failed', error: 'ask closed before delivery' });
    expect(notified).not.toContain(id);
  });
});
