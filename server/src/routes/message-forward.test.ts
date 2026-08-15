// Tests for message forwarding helpers and the agent forward endpoint.
// Covers helper validation plus route-level forwarding, ownership, and missing-message checks.
// Depends on cloudflare:test env, seeded D1 state, shared auth helpers, and mocked fetch.

import { env, SELF } from 'cloudflare:test';
import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { authHeaders, getTestAgentId, seedDatabase } from '../test-helpers';
import { hashApiKey } from '../middleware/auth';
import type { MessageRow } from '../types';
import { forwardMessage, validateForwardChannel } from './message-forward';

beforeAll(async () => {
  await seedDatabase();
});

afterEach(async () => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
  await env.DB.prepare('DELETE FROM channel_configs WHERE agent_id = ? AND channel IN (?, ?)').bind(getTestAgentId(), 'telegram', 'discord').run();
  await env.DB.prepare("DELETE FROM channel_configs WHERE agent_id = 'forward-route-owner'").run();
  await env.DB.prepare("DELETE FROM session_events WHERE message_id IN (SELECT id FROM messages WHERE reply_to LIKE 'forward-helper-%' OR reply_to LIKE 'forward-route-%' OR id LIKE 'forward-helper-%' OR id LIKE 'forward-route-%' OR body LIKE 'forward-route:%')").run();
  await env.DB.prepare("DELETE FROM messages WHERE reply_to LIKE 'forward-helper-%'").run();
  await env.DB.prepare("DELETE FROM messages WHERE reply_to LIKE 'forward-route-%'").run();
  await env.DB.prepare("DELETE FROM messages WHERE id LIKE 'forward-helper-%'").run();
  await env.DB.prepare("DELETE FROM messages WHERE id LIKE 'forward-route-%'").run();
  await env.DB.prepare("DELETE FROM messages WHERE body LIKE 'forward-route:%'").run();
  await env.DB.prepare("DELETE FROM audit_log WHERE action = 'message.forward'").run();
});

describe('validateForwardChannel', () => {
  it('accepts telegram and discord only', () => {
    expect(validateForwardChannel('telegram')).toBe('telegram');
    expect(validateForwardChannel('discord')).toBe('discord');
    expect(validateForwardChannel('api')).toBeNull();
  });
});

describe('forwardMessage', () => {
  it('delivers to telegram and persists forwarded metadata', async () => {
    const fileUrl = 'https://files.test/review.pdf';
    await env.DB.prepare(
      "INSERT INTO channel_configs (agent_id, channel, config, enabled) VALUES (?, 'telegram', ?, 1)"
    ).bind(getTestAgentId(), JSON.stringify({ chat_id: 'chat-1', bot_token: 'telegram-token' })).run();
    await env.DB.prepare(
      "INSERT OR IGNORE INTO sessions (id, agent_id, label, status) VALUES ('forward-helper-session', ?, 'forward-helper-session', 'working')"
    ).bind(getTestAgentId()).run();
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, metadata, session_id) VALUES (?, ?, 'agent_to_boss', 'async', 'discord', ?, 'sent', 'normal', ?, ?)"
    ).bind('forward-helper-source', getTestAgentId(), 'Needs review', JSON.stringify({ file_url: fileUrl }), 'forward-helper-session').run();

    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response('{}', { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ result: { message_id: 4242 } }), { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);

    const original = await env.DB.prepare('SELECT * FROM messages WHERE id = ?').bind('forward-helper-source').first<MessageRow>();
    expect(original).toBeTruthy();
    const forwarded = await forwardMessage(env, original as MessageRow, 'telegram');

    expect(forwarded.body).toBe('[Forwarded from discord] Needs review');
    expect(forwarded.channel).toBe('telegram');
    expect(forwarded.status).toBe('delivered');
    expect(forwarded.type).toBe('forwarded');
    expect(forwarded.reply_to).toBe('forward-helper-source');

    const stored = await env.DB
      .prepare('SELECT metadata FROM messages WHERE id = ?')
      .bind(forwarded.id)
      .first<{ metadata: string | null }>();
    const metadata = JSON.parse(stored?.metadata ?? '{}') as Record<string, unknown>;
    expect(metadata.file_url).toBe(fileUrl);
    expect(metadata.telegram_message_id).toBe(4242);
    const event = await env.DB.prepare('SELECT session_id, message_id FROM session_events WHERE message_id = ?')
      .bind(forwarded.id).first<{ session_id: string; message_id: string }>();
    expect(event).toEqual({ session_id: 'forward-helper-session', message_id: forwarded.id });
  });
});

describe('POST /api/messages/:id/forward', () => {
  it('creates a forwarded message linked to the original message', async () => {
    await env.DB.prepare(
      "INSERT INTO channel_configs (agent_id, channel, config, enabled) VALUES (?, 'telegram', ?, 1)"
    ).bind(getTestAgentId(), JSON.stringify({ chat_id: 'forward-route-chat', bot_token: 'forward-route-bot' })).run();
    await env.DB.prepare(
      "INSERT OR IGNORE INTO sessions (id, agent_id, label, status) VALUES ('forward-route-session', ?, 'forward-route-session', 'working')"
    ).bind(getTestAgentId()).run();
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, session_id) VALUES (?, ?, 'agent_to_boss', 'async', 'discord', ?, 'delivered', 'normal', ?)"
    ).bind('forward-route-source', getTestAgentId(), 'forward-route:source-body', 'forward-route-session').run();

    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response('{}', { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ result: { message_id: 71 } }), { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);

    const res = await SELF.fetch('https://test.local/api/messages/forward-route-source/forward', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ channel: 'telegram' }),
    });

    expect(res.status).toBe(201);
    expect(await res.json()).toMatchObject({
      agent_id: getTestAgentId(),
      channel: 'telegram',
      type: 'forwarded',
      reply_to: 'forward-route-source',
      body: '[Forwarded from discord] forward-route:source-body',
    });
    const stored = await env.DB.prepare("SELECT session_id FROM session_events WHERE raw LIKE '%forward-route:source-body%' ORDER BY sequence DESC LIMIT 1").first<{ session_id: string }>();
    expect(stored?.session_id).toBe('forward-route-session');
  });

  it('does not let a different agent forward another agent message', async () => {
    await createAgentHeaders('forward-route-owner', 'hb_forward_owner_key_000000000000');
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, target_agent_id) VALUES (?, ?, 'agent_to_agent', 'async', 'api', ?, 'sent', 'normal', ?)"
    ).bind('forward-route-owned-by-other', 'forward-route-owner', 'forward-route:other-owner', getTestAgentId()).run();

    const res = await SELF.fetch('https://test.local/api/messages/forward-route-owned-by-other/forward', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ channel: 'discord' }),
    });

    expect(res.status).toBe(403);
    expect(await res.text()).toBe('forbidden');
  });

  it('returns 404 when the source message does not exist', async () => {
    const res = await SELF.fetch('https://test.local/api/messages/forward-route-missing/forward', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ channel: 'telegram' }),
    });

    expect(res.status).toBe(404);
    expect(await res.text()).toBe('not found');
  });
});

async function createAgentHeaders(agentId: string, apiKey: string): Promise<Record<string, string>> {
  const keyHash = await hashApiKey(apiKey);
  await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind(agentId, agentId, keyHash)
    .run();
  return {
    Authorization: `Bearer ${apiKey}`,
    'Content-Type': 'application/json',
  };
}
