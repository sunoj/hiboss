// Integration tests for /api/messages endpoints.
// Covers send, list, get, reply, patch, and poll flows.
// Depends on cloudflare:test, test-helpers, and the Hono app.

import { createAgentAuth } from './messages-tests/support';
import './messages-tests/queries';
import './messages-tests/mutations';
import './messages-tests/metadata';
import './messages-tests/idempotency';
import './messages-tests/sessions';
import { env, SELF } from 'cloudflare:test';
import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { seedDatabase, authHeaders } from '../test-helpers';

beforeAll(async () => {
  await seedDatabase();
});

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});


function toUtcTime(value: Date): string {
  return value.toISOString().slice(11, 16);
}

async function setupQuietHoursAgent(agentId: string, apiKey: string): Promise<Record<string, string>> {
  const headers = await createAgentAuth(agentId, apiKey);
  await env.DB.prepare(
    'INSERT OR REPLACE INTO channel_configs (id, agent_id, channel, config, enabled) VALUES (?, ?, ?, ?, 1)'
  ).bind(`cfg-${agentId}`, agentId, 'api', JSON.stringify({})).run();

  const now = new Date();
  const quietStart = new Date(now.getTime() - 60_000);
  const quietEnd = new Date(now.getTime() + 60_000);
  await env.DB.prepare(
    'INSERT OR REPLACE INTO bosses (id, name, role, preferences) VALUES (?, ?, ?, ?)'
  ).bind(
    `boss-${agentId}`,
    `Boss ${agentId}`,
    'manager',
    JSON.stringify({
      quiet_hours_start: toUtcTime(quietStart),
      quiet_hours_end: toUtcTime(quietEnd),
      timezone: 'UTC',
    }),
  ).run();
  await env.DB.prepare(
    'INSERT OR REPLACE INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)'
  ).bind(`boss-${agentId}`, agentId).run();
  return headers;
}

describe('POST /api/messages', () => {
  it('creates a message with defaults', async () => {
    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Hello boss' }),
    });
    expect(res.status).toBe(201);
    const data = await res.json() as { id: string; status: string; created_at: string };
    expect(data.id).toBeTruthy();
    expect(data.status).toBe('sent');
    expect(data.created_at).toBeTruthy();
  });

  it('rejects empty body', async () => {
    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: '' }),
    });
    expect(res.status).toBe(400);
  });

  it('rejects missing body', async () => {
    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({}),
    });
    expect(res.status).toBe(400);
  });

  it('accepts priority and mode', async () => {
    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Urgent!', priority: 'high', mode: 'blocking' }),
    });
    expect(res.status).toBe(201);
  });

  it('resolves a session by project label prefix and returns the target', async () => {
    await createAgentAuth('address-peer', 'hb_test_key_address_peer_000000');
    await env.DB.prepare(
      "INSERT OR REPLACE INTO sessions (id, agent_id, label, status, last_seen_at) VALUES (?, ?, ?, 'working', datetime('now'))"
    ).bind('address-peer-main', 'address-peer', 'address-project/main').run();

    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Prefix target', to: 'address-project' }),
    });
    expect(res.status).toBe(201);
    const data = await res.json() as { status: string; target: { label: string; id: string } };
    expect(data.status).toBe('sent');
    expect(data.target).toEqual({ label: 'address-project/main', id: 'address-peer-main' });
  });

  it('rejects ambiguous session label prefixes with candidates', async () => {
    await env.DB.prepare(
      "INSERT OR REPLACE INTO sessions (id, agent_id, label, status, last_seen_at) VALUES (?, ?, ?, 'working', datetime('now'))"
    ).bind('ambiguous-main', 'address-peer', 'ambiguous/main').run();
    await env.DB.prepare(
      "INSERT OR REPLACE INTO sessions (id, agent_id, label, status, last_seen_at) VALUES (?, ?, ?, 'working', datetime('now', '-1 minute'))"
    ).bind('ambiguous-review', 'address-peer', 'ambiguous/review').run();
    await env.DB.prepare(
      "INSERT OR REPLACE INTO sessions (id, agent_id, label, status, last_seen_at) VALUES (?, ?, ?, 'completed', datetime('now', '-1 day'))"
    ).bind('ambiguous-stale', 'address-peer', 'ambiguous/stale').run();

    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Ambiguous target', to: 'ambiguous' }),
    });
    expect(res.status).toBe(409);
    await expect(res.json()).resolves.toEqual({
      error: 'ambiguous_target',
      target: 'ambiguous',
      candidates: [
        { label: 'ambiguous/main', id: 'ambiguou' },
        { label: 'ambiguous/review', id: 'ambiguou' },
      ],
      remaining: 0,
    });
  });

  it('delivers to the only active session when stale sessions share its label prefix', async () => {
    await createAgentAuth('stale-peer-target', 'hb_test_key_stale_target_peer_000000');
    for (const [id, label] of [
      ['stale-target-old', 'stale-target/old'],
      ['stale-target-review', 'stale-target/review'],
      ['stale-target-archive', 'stale-target/archive'],
    ]) {
      await env.DB.prepare(
        "INSERT OR REPLACE INTO sessions (id, agent_id, label, status, last_seen_at) VALUES (?, ?, ?, 'completed', datetime('now', '-1 day'))"
      ).bind(id, 'stale-peer-target', label).run();
    }
    await env.DB.prepare(
      "INSERT OR REPLACE INTO sessions (id, agent_id, label, status, last_seen_at) VALUES (?, ?, ?, 'working', datetime('now'))"
    ).bind('stale-target-live', 'stale-peer-target', 'stale-target/main').run();

    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Active target', to: 'stale-target' }),
    });
    expect(res.status).toBe(201);
    const data = await res.json() as { target: { label: string; id: string } };
    expect(data.target).toEqual({ label: 'stale-target/main', id: 'stale-target-live' });
  });

  it('delivers to a stale matching session with a staleness warning', async () => {
    await createAgentAuth('idle-peer-target', 'hb_test_key_idle_target_peer_000000');
    await env.DB.prepare(
      "INSERT OR REPLACE INTO sessions (id, agent_id, label, status, last_seen_at) VALUES (?, ?, ?, 'working', datetime('now', '-1 hour'))"
    ).bind('idle-target-session', 'idle-peer-target', 'idle-target/main').run();

    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Stale target', to: 'idle-target' }),
    });
    expect(res.status).toBe(201);
    const data = await res.json() as { target: { label: string; id: string }; warning: string };
    expect(data.target).toEqual({ label: 'idle-target/main', id: 'idle-target-session' });
    expect(data.warning).toContain("target session 'idle-target' last seen");
  });

  it('caps ambiguous target candidates and reports the remaining active sessions', async () => {
    await createAgentAuth('capped-peer-target', 'hb_test_key_capped_target_peer_000000');
    for (let index = 0; index < 12; index += 1) {
      await env.DB.prepare(
        "INSERT OR REPLACE INTO sessions (id, agent_id, label, status, last_seen_at) VALUES (?, ?, ?, 'working', datetime('now'))"
      ).bind(`capped-target-${index}`, 'capped-peer-target', `capped-target/session-${index}`).run();
    }

    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Capped target', to: 'capped-target' }),
    });
    expect(res.status).toBe(409);
    const data = await res.json() as { candidates: { label: string; id: string }[]; remaining: number };
    expect(data.candidates).toHaveLength(10);
    expect(data.remaining).toBe(2);
  });

  it('lists active session targets when no target matches', async () => {
    await env.DB.prepare(
      "INSERT OR REPLACE INTO sessions (id, agent_id, label, status, last_seen_at) VALUES (?, ?, ?, 'working', datetime('now'))"
    ).bind('suggest-peer-id', 'address-peer', 'suggest-project/main').run();

    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Missing target', to: 'not-a-target' }),
    });
    expect(res.status).toBe(404);
    const data = await res.json() as {
      error: string;
      target: string;
      candidates: { label: string; id: string }[];
      remaining: number;
    };
    expect(data).toMatchObject({
      error: 'target_not_found',
      target: 'not-a-target',
      candidates: expect.any(Array),
      remaining: expect.any(Number),
    });
    expect(data.candidates.length).toBeLessThanOrEqual(10);
  });

  it('queues normal-priority delivery when a boss is in quiet hours', async () => {
    const quietHeaders = await setupQuietHoursAgent('quiet-agent-normal', 'hb_test_key_quiet_normal_000000');

    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: quietHeaders,
      body: JSON.stringify({ body: 'Queue this for later' }),
    });
    expect(res.status).toBe(201);
    const data = await res.json() as { id: string };

    const queueRow = await env.DB
      .prepare('SELECT channel, status, scheduled_at FROM delivery_queue WHERE message_id = ?')
      .bind(data.id)
      .first<{ channel: string; status: string; scheduled_at: string }>();
    expect(queueRow?.channel).toBe('api');
    expect(queueRow?.status).toBe('pending');
    expect(new Date(queueRow!.scheduled_at).getTime()).toBeGreaterThan(Date.now());

    const messageRow = await env.DB
      .prepare('SELECT status FROM messages WHERE id = ?')
      .bind(data.id)
      .first<{ status: string }>();
    expect(messageRow?.status).toBe('sent');
  });

  it('delivers high-priority messages immediately even during quiet hours', async () => {
    const quietHeaders = await setupQuietHoursAgent('quiet-agent-high', 'hb_test_key_quiet_high_000000');

    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: quietHeaders,
      body: JSON.stringify({ body: 'Deliver now', priority: 'high' }),
    });
    expect(res.status).toBe(201);
    const data = await res.json() as { id: string };

    const queueCount = await env.DB
      .prepare('SELECT COUNT(*) AS total FROM delivery_queue WHERE message_id = ?')
      .bind(data.id)
      .first<{ total: number }>();
    expect(queueCount?.total).toBe(0);

    const messageRow = await env.DB
      .prepare('SELECT status FROM messages WHERE id = ?')
      .bind(data.id)
      .first<{ status: string }>();
    expect(messageRow?.status).toBe('delivered');
  });
});
