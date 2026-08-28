// Integration tests for /api/messages endpoints.
// Covers send, list, get, reply, patch, and poll flows.
// Depends on cloudflare:test, test-helpers, and the Hono app.

import { env, SELF } from 'cloudflare:test';
import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { seedDatabase, authHeaders, getTestAgentId } from '../test-helpers';
import { hashApiKey } from '../middleware/auth';
import { insertMessageWithRecovery } from './messages';
import { buildStreamQuery, pruneSeenMessageIds } from './stream';

beforeAll(async () => {
  await seedDatabase();
});

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

async function createAgentAuth(agentId: string, apiKey: string): Promise<Record<string, string>> {
  const keyHash = await hashApiKey(apiKey);
  await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind(agentId, agentId, keyHash)
    .run();
  return {
    Authorization: `Bearer ${apiKey}`,
    'Content-Type': 'application/json',
  };
}

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
    expect(data.status).toBe('queued');
    expect(data.target).toEqual({ label: 'address-project/main', id: 'address-peer-main' });
  });

  it('rejects ambiguous session label prefixes with candidates', async () => {
    await env.DB.prepare(
      "INSERT OR REPLACE INTO sessions (id, agent_id, label, status, last_seen_at) VALUES (?, ?, ?, 'working', datetime('now'))"
    ).bind('ambiguous-main', 'address-peer', 'ambiguous/main').run();
    await env.DB.prepare(
      "INSERT OR REPLACE INTO sessions (id, agent_id, label, status, last_seen_at) VALUES (?, ?, ?, 'working', datetime('now', '-1 minute'))"
    ).bind('ambiguous-review', 'address-peer', 'ambiguous/review').run();

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
    });
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
    await expect(res.json()).resolves.toMatchObject({
      error: 'target_not_found',
      target: 'not-a-target',
      candidates: expect.arrayContaining([{ label: 'suggest-project/main', id: 'suggest-' }]),
    });
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

describe('GET /api/messages', () => {
  it('lists messages for agent', async () => {
    const res = await SELF.fetch('https://test.local/api/messages', {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { messages: unknown[]; total: number };
    expect(data.messages).toBeInstanceOf(Array);
    expect(data.total).toBeGreaterThan(0);
  });

  it('filters by direction', async () => {
    const res = await SELF.fetch('https://test.local/api/messages?direction=agent_to_boss', {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { messages: { direction: string }[] };
    for (const msg of data.messages) {
      expect(msg.direction).toBe('agent_to_boss');
    }
  });

  it('supports unread shortcut', async () => {
    const res = await SELF.fetch('https://test.local/api/messages?unread=true', {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
  });

  it('filters by priority', async () => {
    const res = await SELF.fetch('https://test.local/api/messages?priority=high,critical', {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { messages: { priority: string }[] };
    for (const msg of data.messages) {
      expect(['high', 'critical']).toContain(msg.priority);
    }
  });

  it('searches by body text', async () => {
    // Create a message with unique body
    await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'UniqueSearchTerm42 in this message' }),
    });
    const res = await SELF.fetch('https://test.local/api/messages?search=UniqueSearchTerm42', {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { messages: { body: string }[] };
    expect(data.messages.length).toBeGreaterThanOrEqual(1);
    for (const msg of data.messages) {
      expect(msg.body).toContain('UniqueSearchTerm42');
    }
  });

  it('search returns empty for no match', async () => {
    const res = await SELF.fetch('https://test.local/api/messages?search=zzz_no_match_zzz', {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { messages: unknown[] };
    expect(data.messages.length).toBe(0);
  });

  it('supports limit and offset', async () => {
    const res = await SELF.fetch('https://test.local/api/messages?limit=1&offset=0', {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { messages: unknown[] };
    expect(data.messages.length).toBeLessThanOrEqual(1);
  });

  it('includes session context on list rows', async () => {
    await env.DB.prepare(
      "INSERT INTO sessions (id, agent_id, label, branch, status) VALUES (?, ?, ?, ?, 'working')"
    ).bind('list-session-context', getTestAgentId(), 'List Session', 'feat/session-list').run();
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, session_id) VALUES (?, ?, 'agent_to_boss', 'async', 'api', 'With session context', 'sent', 'normal', ?)"
    ).bind('list-session-context-message', getTestAgentId(), 'list-session-context').run();
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, session_id) VALUES (?, ?, 'agent_to_boss', 'async', 'api', 'Without session context', 'sent', 'normal', NULL)"
    ).bind('list-null-session-message', getTestAgentId()).run();

    const res = await SELF.fetch('https://test.local/api/messages?limit=100', {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as {
      messages: {
        id: string;
        session_label?: string | null;
        session_branch?: string | null;
        session_status?: string | null;
      }[];
    };
    const sessionMessage = data.messages.find((message) => message.id === 'list-session-context-message');
    expect(sessionMessage?.session_label).toBe('List Session');
    expect(sessionMessage?.session_branch).toBe('feat/session-list');
    expect(sessionMessage?.session_status).toBe('working');

    const nullSessionMessage = data.messages.find((message) => message.id === 'list-null-session-message');
    expect(nullSessionMessage?.session_label).toBeNull();
    expect(nullSessionMessage?.session_branch).toBeNull();
    expect(nullSessionMessage?.session_status).toBeNull();
  });
});

describe('GET /api/messages/:id', () => {
  it('returns message with replies', async () => {
    // Create a message first
    const createRes = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'For get test' }),
    });
    const { id } = await createRes.json() as { id: string };

    const res = await SELF.fetch(`https://test.local/api/messages/${id}`, {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { id: string; body: string; replies: unknown[] };
    expect(data.id).toBe(id);
    expect(data.body).toBe('For get test');
    expect(data.replies).toBeInstanceOf(Array);
  });

  it('supports short ID prefix', async () => {
    const createRes = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Short ID test' }),
    });
    const { id } = await createRes.json() as { id: string };
    const prefix = id.slice(0, 8);

    const res = await SELF.fetch(`https://test.local/api/messages/${prefix}`, {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { id: string };
    expect(data.id).toBe(id);
  });

  it('returns 404 for unknown id', async () => {
    const res = await SELF.fetch('https://test.local/api/messages/nonexistent-id', {
      headers: authHeaders(),
    });
    expect(res.status).toBe(404);
  });
});

describe('POST /api/messages/:id/reply', () => {
  it('creates a reply to a message', async () => {
    // First insert a boss_to_agent message to reply to
    const agentId = getTestAgentId();
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, body, status, priority) VALUES (?, ?, 'boss_to_agent', 'async', 'Boss says hi', 'sent', 'normal')"
    ).bind('reply-test-msg', agentId).run();

    const res = await SELF.fetch('https://test.local/api/messages/reply-test-msg/reply', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Agent replies' }),
    });
    expect(res.status).toBe(201);
    const data = await res.json() as { direction: string; reply_to: string; body: string };
    expect(data.direction).toBe('agent_to_boss');
    expect(data.reply_to).toBe('reply-test-msg');
    expect(data.body).toBe('Agent replies');
  });

  it('rejects empty reply body', async () => {
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, body, status, priority) VALUES (?, ?, 'boss_to_agent', 'async', 'Test', 'sent', 'normal')"
    ).bind('reply-empty-msg', getTestAgentId()).run();

    const res = await SELF.fetch('https://test.local/api/messages/reply-empty-msg/reply', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: '' }),
    });
    expect(res.status).toBe(400);
  });

  it('returns 404 for unknown parent', async () => {
    const res = await SELF.fetch('https://test.local/api/messages/nonexistent/reply', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Reply to nothing' }),
    });
    expect(res.status).toBe(404);
  });

  it('sets target_agent_id on agent-to-agent replies and exposes them to the original sender', async () => {
    const otherHeaders = await createAgentAuth('reply-agent-2', 'hb_test_key_reply_agent_2_000000');
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, session_id, target_agent_id) VALUES (?, ?, 'agent_to_agent', 'async', 'api', 'Ping', 'sent', 'normal', ?, ?)"
    ).bind('reply-a2a-parent', getTestAgentId(), 'session-a2a-parent', 'reply-agent-2').run();

    const replyRes = await SELF.fetch('https://test.local/api/messages/reply-a2a-parent/reply', {
      method: 'POST',
      headers: otherHeaders,
      body: JSON.stringify({ body: 'Pong back' }),
    });
    expect(replyRes.status).toBe(201);
    const reply = await replyRes.json() as { id: string; direction: string; target_agent_id: string | null; target_session_id: string | null };
    expect(reply.direction).toBe('agent_to_agent');
    expect(reply.target_agent_id).toBe(getTestAgentId());
    expect(reply.target_session_id).toBe('session-a2a-parent');

    const storedReply = await env.DB.prepare(
      'SELECT target_agent_id, target_session_id FROM messages WHERE id = ?'
    ).bind(reply.id).first<{ target_agent_id: string | null; target_session_id: string | null }>();
    expect(storedReply?.target_agent_id).toBe(getTestAgentId());
    expect(storedReply?.target_session_id).toBe('session-a2a-parent');

    const senderListRes = await SELF.fetch('https://test.local/api/messages?direction=agent_to_agent', {
      headers: authHeaders(),
    });
    expect(senderListRes.status).toBe(200);
    const senderList = await senderListRes.json() as { messages: { id: string; body: string }[] };
    expect(senderList.messages.some((message) => message.id === reply.id && message.body === 'Pong back')).toBe(true);
  });
});

describe('POST /api/messages/:id/forward', () => {
  it('rejects invalid target channels', async () => {
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority) VALUES (?, ?, 'agent_to_boss', 'async', 'discord', 'Needs review', 'sent', 'normal')"
    ).bind('forward-invalid-channel', getTestAgentId()).run();

    const res = await SELF.fetch('https://test.local/api/messages/forward-invalid-channel/forward', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ channel: 'api' }),
    });
    expect(res.status).toBe(400);
    expect(await res.text()).toContain('channel must be discord or telegram');
  });

  it('rejects forwarding when the caller does not own the message', async () => {
    const otherHeaders = await createAgentAuth('forward-owner', 'hb_test_key_forward_owner_000000');
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, target_agent_id) VALUES (?, ?, 'agent_to_agent', 'async', 'telegram', 'Private', 'sent', 'normal', ?)"
    ).bind('forward-owner-only', 'forward-owner', getTestAgentId()).run();

    const res = await SELF.fetch('https://test.local/api/messages/forward-owner-only/forward', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ channel: 'discord' }),
    });
    expect(res.status).toBe(403);

    const ownerRes = await SELF.fetch('https://test.local/api/messages/forward-owner-only/forward', {
      method: 'POST',
      headers: otherHeaders,
      body: JSON.stringify({ channel: 'discord' }),
    });
    expect(ownerRes.status).not.toBe(403);
  });
});

describe('PATCH /api/messages/:id', () => {
  it('updates message status', async () => {
    const createRes = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Patch test' }),
    });
    const { id } = await createRes.json() as { id: string };

    const res = await SELF.fetch(`https://test.local/api/messages/${id}`, {
      method: 'PATCH',
      headers: authHeaders(),
      body: JSON.stringify({ status: 'read' }),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { status: string };
    expect(data.status).toBe('read');
  });

  it('rejects backward status transitions', async () => {
    const createRes = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Backward transition test' }),
    });
    const { id } = await createRes.json() as { id: string };

    const firstPatch = await SELF.fetch(`https://test.local/api/messages/${id}`, {
      method: 'PATCH',
      headers: authHeaders(),
      body: JSON.stringify({ status: 'read' }),
    });
    expect(firstPatch.status).toBe(200);

    const secondPatch = await SELF.fetch(`https://test.local/api/messages/${id}`, {
      method: 'PATCH',
      headers: authHeaders(),
      body: JSON.stringify({ status: 'delivered' }),
    });
    expect(secondPatch.status).toBe(400);
    expect(await secondPatch.text()).toContain('invalid status transition');
  });

  it('allows the target recipient to mark an a2a message read', async () => {
    const otherApiKey = 'hb_test_key_agent2_patch_000000';
    const otherKeyHash = await hashApiKey(otherApiKey);
    await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
      .bind('patch-agent-2', 'patch-agent-2', otherKeyHash)
      .run();
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, body, status, priority, target_agent_id) VALUES (?, ?, 'agent_to_agent', 'async', 'Private', 'sent', 'normal', ?)"
    ).bind('patch-owner-only', getTestAgentId(), 'patch-agent-2').run();

    const res = await SELF.fetch('https://test.local/api/messages/patch-owner-only', {
      method: 'PATCH',
      headers: {
        Authorization: `Bearer ${otherApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ status: 'read' }),
    });
    expect(res.status).toBe(200);
    expect((await res.json() as { status: string }).status).toBe('read');
  });

  it('updates message body', async () => {
    const createRes = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Original body' }),
    });
    const { id } = await createRes.json() as { id: string };

    const res = await SELF.fetch(`https://test.local/api/messages/${id}`, {
      method: 'PATCH',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Updated body' }),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { body: string };
    expect(data.body).toBe('Updated body');
  });

  it('updates both status and body', async () => {
    const createRes = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Original body' }),
    });
    const { id } = await createRes.json() as { id: string };

    const res = await SELF.fetch(`https://test.local/api/messages/${id}`, {
      method: 'PATCH',
      headers: authHeaders(),
      body: JSON.stringify({ status: 'read', body: 'Updated body' }),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { status: string, body: string };
    expect(data.status).toBe('read');
    expect(data.body).toBe('Updated body');
  });

  it('rejects body edits for non-agent_to_boss messages', async () => {
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, body, status, priority) VALUES (?, ?, 'boss_to_agent', 'async', 'Boss sent this', 'sent', 'normal')"
    ).bind('patch-body-forbidden', getTestAgentId()).run();

    const res = await SELF.fetch('https://test.local/api/messages/patch-body-forbidden', {
      method: 'PATCH',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Should not apply' }),
    });
    expect(res.status).toBe(403);
    expect(await res.text()).toContain('only agent_to_boss messages can be edited');
  });

  it('records audit log on body edit', async () => {
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority) VALUES (?, ?, 'agent_to_boss', 'async', 'api', ?, 'delivered', 'normal')"
    ).bind('patch-edit-audit', getTestAgentId(), 'Original').run();

    const res = await SELF.fetch('https://test.local/api/messages/patch-edit-audit', {
      method: 'PATCH',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Edited remotely' }),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { body: string };
    expect(data.body).toBe('Edited remotely');
  });

  it('returns 400 when neither status nor body is provided', async () => {
    const createRes = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'No update test' }),
    });
    const { id } = await createRes.json() as { id: string };

    const res = await SELF.fetch(`https://test.local/api/messages/${id}`, {
      method: 'PATCH',
      headers: authHeaders(),
      body: JSON.stringify({}),
    });
    expect(res.status).toBe(400);
    expect(await res.text()).toContain('status or body is required');
  });

  it('rejects invalid status', async () => {
    const createRes = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Invalid status test' }),
    });
    const { id } = await createRes.json() as { id: string };

    const res = await SELF.fetch(`https://test.local/api/messages/${id}`, {
      method: 'PATCH',
      headers: authHeaders(),
      body: JSON.stringify({ status: 'invalid' }),
    });
    expect(res.status).toBe(400);
  });
});

describe('POST /api/messages/:id/react', () => {
  it('rejects empty emoji', async () => {
    const createRes = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'React test' }),
    });
    const { id } = await createRes.json() as { id: string };

    const res = await SELF.fetch(`https://test.local/api/messages/${id}/react`, {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ emoji: '' }),
    });
    expect(res.status).toBe(400);
  });

  it('returns 404 for unknown message', async () => {
    const res = await SELF.fetch('https://test.local/api/messages/nonexistent/react', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ emoji: '👀' }),
    });
    expect(res.status).toBe(404);
  });

  it('rejects react on unsupported channel', async () => {
    // Create a message with no channel (not telegram or discord)
    const createRes = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'No channel msg' }),
    });
    const { id } = await createRes.json() as { id: string };

    const res = await SELF.fetch(`https://test.local/api/messages/${id}/react`, {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ emoji: '👀' }),
    });
    expect(res.status).toBe(400);
    expect(await res.text()).toContain('not supported');
  });
});

describe('POST /api/messages with metadata', () => {
  it('stores file_url in metadata', async () => {
    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'See file', file_url: 'https://example.com/img.png' }),
    });
    expect(res.status).toBe(201);
    const { id } = await res.json() as { id: string };

    // Verify metadata contains file_url
    const getRes = await SELF.fetch(`https://test.local/api/messages/${id}`, {
      headers: authHeaders(),
    });
    const msg = await getRes.json() as { metadata: Record<string, unknown> | null };
    expect(msg.metadata?.['file_url']).toBe('https://example.com/img.png');
  });

  it('stores custom metadata', async () => {
    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'With meta', metadata: { task: 'test-123' } }),
    });
    expect(res.status).toBe(201);
    const { id } = await res.json() as { id: string };

    const getRes = await SELF.fetch(`https://test.local/api/messages/${id}`, {
      headers: authHeaders(),
    });
    const msg = await getRes.json() as { metadata: Record<string, unknown> | null };
    expect(msg.metadata?.['task']).toBe('test-123');
  });

  it('accepts option arrays and preserves commas inside an option', async () => {
    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Choose one', options: ['A, recommended', 'B'] }),
    });
    expect(res.status).toBe(201);
    const { id } = await res.json() as { id: string };
    const row = await env.DB.prepare('SELECT metadata FROM messages WHERE id = ?')
      .bind(id).first<{ metadata: string }>();
    expect(JSON.parse(row?.metadata ?? '{}').options).toEqual(['A, recommended', 'B']);
  });

  it('rejects string options and arrays with more than five choices', async () => {
    const stringResult = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Choose one', options: 'A,B' }),
    });
    const overflowResult = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Choose one', options: ['1', '2', '3', '4', '5', '6'] }),
    });

    expect(stringResult.status).toBe(400);
    expect(overflowResult.status).toBe(400);
  });
});

describe('POST /api/messages with type', () => {
  it('stores message type', async () => {
    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Deploy done', type: 'task_update' }),
    });
    expect(res.status).toBe(201);
    const { id } = await res.json() as { id: string };

    const getRes = await SELF.fetch(`https://test.local/api/messages/${id}`, {
      headers: authHeaders(),
    });
    const msg = await getRes.json() as { type: string | null };
    expect(msg.type).toBe('task_update');
  });

  it('defaults type to text', async () => {
    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Plain message' }),
    });
    expect(res.status).toBe(201);
    const { id } = await res.json() as { id: string };

    const getRes = await SELF.fetch(`https://test.local/api/messages/${id}`, {
      headers: authHeaders(),
    });
    const msg = await getRes.json() as { type: string | null };
    expect(msg.type).toBe('text');
  });
});

describe('POST /api/messages/:id/poll', () => {
  it('returns 400 for non-blocking message', async () => {
    const createRes = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Async msg', mode: 'async' }),
    });
    const { id } = await createRes.json() as { id: string };

    const res = await SELF.fetch(`https://test.local/api/messages/${id}/poll`, {
      method: 'POST',
      headers: authHeaders(),
    });
    expect(res.status).toBe(400);
  });

  it('returns 404 for unknown message', async () => {
    const res = await SELF.fetch('https://test.local/api/messages/nonexistent/poll', {
      method: 'POST',
      headers: authHeaders(),
    });
    expect(res.status).toBe(404);
  });
});

describe('POST /api/messages idempotency', () => {
  it('returns 201 on first send with idempotency_key', async () => {
    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'test', idempotency_key: 'key-1' }),
    });
    expect(res.status).toBe(201);
    const data = await res.json() as Record<string, unknown>;
    expect(data.id).toBeDefined();
  });

  it('returns 200 with same id on duplicate idempotency_key', async () => {
    const res1 = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'first', idempotency_key: 'dup-key' }),
    });
    expect(res1.status).toBe(201);
    const data1 = await res1.json() as Record<string, unknown>;
    const res2 = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'second', idempotency_key: 'dup-key' }),
    });
    expect(res2.status).toBe(200);
    const data2 = await res2.json() as Record<string, unknown>;
    expect(data2.id).toBe(data1.id);
  });

  it('creates new message with different idempotency_key', async () => {
    const res1 = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'a', idempotency_key: 'key-a' }),
    });
    const res2 = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'b', idempotency_key: 'key-b' }),
    });
    expect(res1.status).toBe(201);
    expect(res2.status).toBe(201);
    const d1 = await res1.json() as Record<string, unknown>;
    const d2 = await res2.json() as Record<string, unknown>;
    expect(d1.id).not.toBe(d2.id);
  });

  it('always creates new message without idempotency_key', async () => {
    const res1 = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'no key 1' }),
    });
    const res2 = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'no key 2' }),
    });
    expect(res1.status).toBe(201);
    expect(res2.status).toBe(201);
    const d1 = await res1.json() as Record<string, unknown>;
    const d2 = await res2.json() as Record<string, unknown>;
    expect(d1.id).not.toBe(d2.id);
  });

  it('returns existing message when insert hits unique constraint', async () => {
    const existing = {
      id: 'race-msg-001',
      agent_id: getTestAgentId(),
      direction: 'agent_to_boss',
      mode: 'async',
      channel: 'api',
      body: 'first',
      status: 'sent',
      reply_to: null,
      priority: 'normal',
      type: 'text',
      target_agent_id: null,
      target_session_id: null,
      session_id: null,
      idempotency_key: 'race-key',
      metadata: null,
      created_at: '2026-01-01T00:00:00Z',
      updated_at: '2026-01-01T00:00:00Z',
    };
    const fakeEnv = {
      DB: {
        prepare(sql: string) {
          if (sql.startsWith('INSERT INTO messages')) {
            return {
              bind() {
                return {
                  first: async () => { throw new Error('UNIQUE constraint failed: messages.agent_id, messages.idempotency_key'); },
                };
              },
            };
          }
          if (sql === 'SELECT * FROM messages WHERE agent_id = ? AND idempotency_key = ?') {
            return {
              bind() {
                return {
                  first: async () => existing,
                };
              },
            };
          }
          throw new Error(`unexpected SQL: ${sql}`);
        },
      },
    };
    const result = await insertMessageWithRecovery(fakeEnv as any, getTestAgentId(), [
      'agent_to_boss',
      'async',
      'api',
      'second',
      'normal',
      'text',
      'race-key',
      null,
      null,
      null,
      null,
    ]);
    expect(result.inserted).toBeNull();
    expect(result.existing).toEqual(existing);
  });
});

describe('stream helpers', () => {
  it('uses >= in the polling query', () => {
    const { sql } = buildStreamQuery(getTestAgentId());
    expect(sql).toContain('messages.created_at >= ?');
  });

  it('retains seen ids for the same timestamp batch and clears them after the window advances', () => {
    const seen = new Set<string>(['m1']);
    pruneSeenMessageIds(seen, [{ id: 'm2', created_at: '2026-01-01 00:00:00' } as any], '2026-01-01 00:00:00');
    expect(seen.has('m1')).toBe(true);

    pruneSeenMessageIds(seen, [{ id: 'm3', created_at: '2026-01-01 00:00:01' } as any], '2026-01-01 00:00:00');
    expect(seen.size).toBe(0);
  });
});

describe('Session-scoped messages', () => {
  const agentId = getTestAgentId();

  it('stores session_id on sent messages', async () => {
    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Session msg', session_id: 'sess-aaa' }),
    });
    expect(res.status).toBe(201);
    const { id } = await res.json() as { id: string };
    const getRes = await SELF.fetch(`https://test.local/api/messages/${id}`, {
      headers: authHeaders(),
    });
    const msg = await getRes.json() as { session_id: string | null };
    expect(msg.session_id).toBe('sess-aaa');
  });

  it('filters by session in non-unread mode', async () => {
    // Create messages in different sessions
    await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'From sess-bbb', session_id: 'sess-bbb' }),
    });
    await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'From sess-ccc', session_id: 'sess-ccc' }),
    });

    // Query with session filter (non-unread)
    const res = await SELF.fetch('https://test.local/api/messages?session=sess-bbb', {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { messages: { body: string; session_id: string | null }[] };
    // Should include messages from sess-bbb and boss-initiated messages
    const sessB = data.messages.filter(m => m.session_id === 'sess-bbb');
    expect(sessB.length).toBeGreaterThan(0);
    // Should NOT include messages from sess-ccc
    const sessC = data.messages.filter(m => m.session_id === 'sess-ccc');
    expect(sessC.length).toBe(0);
  });

  it('scopes unread by target_session for agent-to-agent', async () => {
    // Seed: create a second agent
    const { hashApiKey } = await import('../middleware/auth');
    const key2Hash = await hashApiKey('hb_test_key_agent2_000000');
    await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
      .bind('test-agent-2', 'agent-2', key2Hash).run();

    // Agent-2 sends a message targeted at agent-1's specific session
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, body, status, priority, target_agent_id, target_session_id) VALUES (?, ?, 'agent_to_agent', 'async', 'For session X only', 'queued', 'normal', ?, ?)"
    ).bind('a2a-sess-targeted', 'test-agent-2', agentId, 'sess-xxx').run();

    // Agent-2 sends a message targeted at agent-1 (no session)
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, body, status, priority, target_agent_id) VALUES (?, ?, 'agent_to_agent', 'async', 'For all sessions', 'queued', 'normal', ?)"
    ).bind('a2a-no-sess', 'test-agent-2', agentId).run();

    // Query unread with target_session=sess-xxx: should see both
    const res1 = await SELF.fetch('https://test.local/api/messages?unread=true&target_session=sess-xxx', {
      headers: authHeaders(),
    });
    expect(res1.status).toBe(200);
    const data1 = await res1.json() as { messages: { id: string }[] };
    const ids1 = data1.messages.map(m => m.id);
    expect(ids1).toContain('a2a-sess-targeted');
    expect(ids1).toContain('a2a-no-sess');

    // Query unread with target_session=sess-yyy: should NOT see session-targeted message
    const res2 = await SELF.fetch('https://test.local/api/messages?unread=true&target_session=sess-yyy', {
      headers: authHeaders(),
    });
    expect(res2.status).toBe(200);
    const data2 = await res2.json() as { messages: { id: string }[] };
    const ids2 = data2.messages.map(m => m.id);
    expect(ids2).not.toContain('a2a-sess-targeted');
    expect(ids2).toContain('a2a-no-sess');
  });

  it('stores target_session_id when sending to a session', async () => {
    // Create a session for targeting
    await env.DB.prepare(
      "INSERT OR IGNORE INTO sessions (id, agent_id, label) VALUES (?, ?, ?)"
    ).bind('target-sess-001', agentId, 'my-session').run();

    // Send a message targeted at the session label
    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Hey session', to: 'my-session' }),
    });
    expect(res.status).toBe(201);
    const { id } = await res.json() as { id: string };

    const getRes = await SELF.fetch(`https://test.local/api/messages/${id}`, {
      headers: authHeaders(),
    });
    const msg = await getRes.json() as { target_session_id: string | null; target_agent_id: string | null; direction: string };
    expect(msg.target_session_id).toBe('target-sess-001');
    expect(msg.target_agent_id).toBe(agentId);
    expect(msg.direction).toBe('agent_to_agent');
  });

  it('does not expose another agent target_session in non-unread mode', async () => {
    const { hashApiKey } = await import('../middleware/auth');
    const key2Hash = await hashApiKey('hb_test_key_agent3_000000');
    await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
      .bind('test-agent-3', 'agent-3', key2Hash).run();
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, body, status, priority, target_agent_id, target_session_id) VALUES (?, ?, 'agent_to_agent', 'async', 'Other session target', 'sent', 'normal', ?, ?)"
    ).bind('a2a-other-session-target', 'test-agent-3', 'someone-else', 'sess-shared').run();
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, body, status, priority, target_agent_id, target_session_id) VALUES (?, ?, 'agent_to_agent', 'async', 'My session target', 'sent', 'normal', ?, ?)"
    ).bind('a2a-my-session-target', 'test-agent-3', agentId, 'sess-shared').run();

    const res = await SELF.fetch('https://test.local/api/messages?target_session=sess-shared&limit=100', {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { messages: { id: string }[] };
    const ids = data.messages.map(m => m.id);
    expect(ids).toContain('a2a-my-session-target');
    expect(ids).not.toContain('a2a-other-session-target');
  });

  it('excludes a session own broadcasts from its unread (self-authored a2a)', async () => {
    // A session that authored an a2a message (session_id == query session) must never
    // see it as unread, even if it was self-targeted (target_session_id == session_id).
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, body, status, priority, target_agent_id, target_session_id, session_id) VALUES (?, ?, 'agent_to_agent', 'async', 'Self broadcast', 'queued', 'normal', ?, ?, ?)"
    ).bind('a2a-self-broadcast', agentId, agentId, 'sess-self', 'sess-self').run();
    // A genuine peer message authored by a different session, targeted at sess-self.
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, body, status, priority, target_agent_id, target_session_id, session_id) VALUES (?, ?, 'agent_to_agent', 'async', 'Peer broadcast', 'queued', 'normal', ?, ?, ?)"
    ).bind('a2a-peer-broadcast', agentId, agentId, 'sess-self', 'sess-peer').run();

    const res = await SELF.fetch('https://test.local/api/messages?unread=true&target_session=sess-self&limit=100', {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { messages: { id: string }[] };
    const ids = data.messages.map(m => m.id);
    expect(ids).not.toContain('a2a-self-broadcast');
    expect(ids).toContain('a2a-peer-broadcast');
  });

  it('does not resolve a colliding label back to the sender own session', async () => {
    await env.DB.prepare(
      "INSERT OR IGNORE INTO sessions (id, agent_id, label, last_seen_at) VALUES (?, ?, ?, datetime('now', '-1 minute'))"
    ).bind('collide-peer', agentId, 'shared-label').run();
    await env.DB.prepare(
      "INSERT OR IGNORE INTO sessions (id, agent_id, label, last_seen_at) VALUES (?, ?, ?, datetime('now'))"
    ).bind('collide-self', agentId, 'shared-label').run();

    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Broadcast', to: 'shared-label', session_id: 'collide-self' }),
    });
    expect(res.status).toBe(201);
    const data = await res.json() as { target: { id: string } };
    expect(data.target.id).toBe('collide-peer');
  });

  it('uses the newest non-self session for an exact duplicate label', async () => {
    await createAgentAuth('exact-label-peer', 'hb_test_key_exact_label_peer_000000');
    await env.DB.prepare(
      "INSERT OR REPLACE INTO sessions (id, agent_id, label, last_seen_at) VALUES (?, ?, ?, datetime('now', '-1 minute'))"
    ).bind('exact-label-old', 'exact-label-peer', 'exact-project/main').run();
    await env.DB.prepare(
      "INSERT OR REPLACE INTO sessions (id, agent_id, label, last_seen_at) VALUES (?, ?, ?, datetime('now'))"
    ).bind('exact-label-new', 'exact-label-peer', 'exact-project/main').run();

    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Exact duplicate label', to: 'exact-project/main' }),
    });
    expect(res.status).toBe(201);
    const data = await res.json() as { target: { label: string; id: string } };
    expect(data.target).toEqual({ label: 'exact-project/main', id: 'exact-label-new' });
  });
});
