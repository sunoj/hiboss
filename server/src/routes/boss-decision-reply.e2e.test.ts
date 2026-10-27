// HTTP regression coverage for definitive decision closure and stale decisions.
// Exercises blocking and option asks, ordinary replies, and agent delivery side effects.
// Depends on the Worker API, seeded D1 sessions, boss auth, and mocked callbacks.

import { testRequest, testJson } from '../test-request';
import { env, SELF } from 'cloudflare:test';
import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { getTestAgentId, seedBossToken, seedDatabase } from '../test-helpers';
import type { MessageRow } from '../types';

const TOKEN = `hb_boss_closed_decision_${'ab'.repeat(8)}`;
const SESSION_ID = 'closed-decision-session';
const HEADERS = { Authorization: `Bearer ${TOKEN}`, 'Content-Type': 'application/json' };
const FUTURE = new Date(Date.now() + 3_600_000).toISOString();
const PAST = new Date(Date.now() - 3_600_000).toISOString();

beforeAll(async () => {
  await seedDatabase();
  await seedBossToken('Decision Reply Boss', 'admin', TOKEN);
  await env.DB.prepare(
    "INSERT INTO sessions (id, agent_id, label, status) VALUES (?, ?, 'Decision replies', 'working')",
  ).bind(SESSION_ID, getTestAgentId()).run();
});

afterEach(async () => {
  await env.DB.prepare('UPDATE api_keys SET callback_url = NULL WHERE id = ?')
    .bind(getTestAgentId()).run();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

describe('boss decision reply closure', () => {
  it('rejects a second blocking answer without inserting or delivering another reply', async () => {
    const id = await insertParent({ mode: 'blocking' });
    const callback = vi.fn().mockResolvedValue(new Response('{}', { status: 200 }));
    vi.stubGlobal('fetch', callback);
    await env.DB.prepare('UPDATE api_keys SET callback_url = ? WHERE id = ?')
      .bind('https://agent.test/decision-callback', getTestAgentId()).run();
    const accepted = await testJson(201, reply(id, 'First answer')) as { id: string };
    await vi.waitFor(() => expect(callback).toHaveBeenCalledTimes(1));
    expect(await parentStatus(id)).toBe('replied');

    const second = await reply(id, 'Second answer');
    expect(second.status).toBe(409);
    expect(await second.text()).toBe('decision no longer open');
    expect(await replyIds(id)).toEqual([accepted.id]);
    expect(await eventCount(id)).toBe(1);
    expect(callback).toHaveBeenCalledTimes(1);
  });

  it.each(['blocking', 'options'] as const)(
    'rejects an expired %s decision whose status is still open', async (shape) => {
      const id = await insertParent({ ...decision(shape), expires_at: PAST });
      await expectClosed(id);
      expect(await parentStatus(id)).toBe('sent');
    },
  );

  it.each(['blocking', 'options'] as const)(
    'rejects a withdrawn %s decision whose status and deadline are still open', async (shape) => {
      const id = await insertParent({ ...decision(shape), expires_at: FUTURE,
        metadata: JSON.stringify({ options_expired: true,
          ...(shape === 'options' ? { options: ['Yes'] } : {}),
        }),
      });
      await expectClosed(id);
      expect(await parentStatus(id)).toBe('sent');
    },
  );

  it.each(['replied', 'expired'] as const)('rejects a decision with %s status', async (status) => {
    const id = await insertParent({ metadata: JSON.stringify({ options: ['Yes'] }), status });
    await expectClosed(id);
  });
});

describe('boss replies to answerable messages', () => {
  it.each(['blocking', 'options'] as const)(
    'accepts a no-deadline %s decision older than the display cutoff', async (shape) => {
      const id = await insertParent({ ...decision(shape),
        created_at: new Date(Date.now() - 48 * 3_600_000).toISOString(),
      });
      const pending = await SELF.fetch('http://localhost/api/boss/pending-inputs', { headers: HEADERS });
      expect(pending.status).toBe(200);
      const page = await pending.json() as { messages: { id: string }[] };
      expect(page.messages.map((message) => message.id)).not.toContain(id);
      const accepted = await reply(id, 'Still waiting');
      expect(accepted.status).toBe(201);
      expect(await parentStatus(id)).toBe('replied');
      expect(await replyIds(id)).toHaveLength(1);
      expect(await eventCount(id)).toBe(1);
    },
  );

  it('accepts an ordinary message despite closed status, deadline, and withdrawn metadata', async () => {
    const id = await insertParent({ status: 'replied', expires_at: PAST,
      metadata: JSON.stringify({ options_expired: true }),
    });
    expect((await reply(id, 'Follow-up')).status).toBe(201);
    expect(await replyIds(id)).toHaveLength(1);
    expect(await eventCount(id)).toBe(1);
  });

  it.each(['sent', 'delivered', 'read'] as const)(
    'accepts an open decision with %s status', async (status) => {
      const id = await insertParent({ mode: 'blocking', status, expires_at: FUTURE });
      expect((await reply(id, 'Yes')).status).toBe(201);
    },
  );

  it('accepts blocking decisions with invalid metadata', async () => {
    const id = await insertParent({ mode: 'blocking', metadata: 'invalid JSON' });
    expect((await reply(id, 'Yes')).status).toBe(201);
  });
});

type ParentFields = Partial<Pick<MessageRow, 'mode' | 'status' | 'metadata' | 'expires_at' | 'created_at'>>;

function decision(shape: 'blocking' | 'options'): ParentFields {
  return shape === 'blocking' ? { mode: 'blocking' } : { metadata: JSON.stringify({ options: ['Yes'] }) };
}

async function insertParent(fields: ParentFields): Promise<string> {
  const id = crypto.randomUUID().replaceAll("-", ""); // production-shaped id; D1 caps LIKE patterns near 50 bytes
  await env.DB.prepare(
    `INSERT INTO messages
     (id, agent_id, direction, mode, channel, body, status, metadata, expires_at, created_at, session_id)
     VALUES (?, ?, 'agent_to_boss', ?, 'api', 'Question', ?, ?, ?, ?, ?)`,
  ).bind(id, getTestAgentId(), fields.mode ?? 'async', fields.status ?? 'sent', fields.metadata ?? null,
    fields.expires_at ?? null, fields.created_at ?? new Date().toISOString(), SESSION_ID).run();
  return id;
}

function reply(id: string, body: string): Promise<Response> {
  return testRequest('POST', `http://localhost/api/boss/messages/${id}/reply`, HEADERS, { body });
}

async function expectClosed(id: string): Promise<void> {
  const response = await reply(id, 'Late answer');
  expect(response.status).toBe(409);
  expect(await response.text()).toBe('decision no longer open');
  expect(await replyIds(id)).toEqual([]);
  expect(await eventCount(id)).toBe(0);
}

async function replyIds(id: string): Promise<string[]> {
  const rows = await env.DB.prepare('SELECT id FROM messages WHERE reply_to = ?')
    .bind(id).all<{ id: string }>();
  return rows.results.map((row) => row.id);
}

async function eventCount(id: string): Promise<number> {
  const row = await env.DB.prepare(
    `SELECT COUNT(*) AS total FROM session_events
     WHERE message_id IN (SELECT id FROM messages WHERE reply_to = ?)`,
  ).bind(id).first<{ total: number }>();
  return row?.total ?? 0;
}

async function parentStatus(id: string): Promise<string | undefined> {
  const row = await env.DB.prepare('SELECT status FROM messages WHERE id = ?')
    .bind(id).first<{ status: string }>();
  return row?.status;
}
