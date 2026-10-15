// Tests for reactions endpoints.
// Covers posting reactions and fetching reactions from metadata.
// Depends on cloudflare:test, vitest, and reactions.ts.

import { describe, it, expect, beforeAll, afterEach, vi } from 'vitest';
import { env, SELF } from 'cloudflare:test';
import { seedDatabase, authHeaders, getTestAgentId } from '../test-helpers';

beforeAll(async () => {
  await seedDatabase();
});
afterEach(() => vi.unstubAllGlobals());

describe('POST /api/messages/:id/react', () => {
  const agentId = getTestAgentId();

  it('returns 400 when emoji missing', async () => {
    // Insert a message to react to
    const msgId = 'react-test-1';
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, body, status, channel) VALUES (?, ?, 'boss_to_agent', 'async', 'Test msg', 'sent', 'telegram')"
    ).bind(msgId, agentId).run();

    const res = await SELF.fetch(`https://test.local/api/messages/${msgId}/react`, {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({}),
    });
    expect(res.status).toBe(400);
    expect(await res.text()).toBe('emoji is required');
  });

  it('returns 404 for unknown message', async () => {
    const res = await SELF.fetch('https://test.local/api/messages/unknown-msg-id/react', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ emoji: '👍' }),
    });
    expect(res.status).toBe(404);
    expect(await res.text()).toBe('not found');
  });

  it('stores agent reactions on API messages', async () => {
    const msgId = 'react-test-api';
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, body, status, channel) VALUES (?, ?, 'boss_to_agent', 'async', 'API msg', 'sent', 'api')"
    ).bind(msgId, agentId).run();

    const res = await SELF.fetch(`https://test.local/api/messages/${msgId}/react`, {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ emoji: '👍' }),
    });
    expect(res.status).toBe(200);
    const row = await env.DB.prepare('SELECT metadata FROM messages WHERE id = ?')
      .bind(msgId).first<{ metadata: string }>();
    expect(JSON.parse(row?.metadata ?? '{}').reactions).toEqual([
      { emoji: '👍', actor: 'agent', actor_id: agentId, created_at: expect.any(String) },
    ]);
  });

  it('retains the stored reaction when Discord forwarding is unavailable', async () => {
    await env.DB.prepare(
      "INSERT OR REPLACE INTO channel_configs (agent_id, channel, config, enabled) VALUES (?, 'discord', ?, 1)"
    ).bind(agentId, JSON.stringify({ webhook_url: 'https://discord.com/api/webhooks/x/y' })).run();
    const msgId = 'react-discord-no-token';
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, body, status, channel, metadata) VALUES (?, ?, 'boss_to_agent', 'async', 'Discord msg', 'sent', 'discord', ?)"
    ).bind(msgId, agentId, JSON.stringify({ discord_message_id: '123' })).run();

    const res = await SELF.fetch(`https://test.local/api/messages/${msgId}/react`, {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ emoji: '👍' }),
    });
    expect(res.status).toBe(200);
    const row = await env.DB.prepare('SELECT metadata FROM messages WHERE id = ?')
      .bind(msgId).first<{ metadata: string }>();
    expect(JSON.parse(row?.metadata ?? '{}').reactions).toHaveLength(1);
  });

  it.each([true, false])('persists Telegram reactions when forwarding succeeds: %s', async succeeds => {
    const id = `react-telegram-${succeeds}`;
    await env.DB.prepare(`INSERT OR REPLACE INTO channel_configs (agent_id, channel, config, enabled)
      VALUES (?, 'telegram', ?, 1)`)
      .bind(agentId, JSON.stringify({ bot_token: 'reaction-test-token', chat_id: 'chat' })).run();
    await env.DB.prepare(`INSERT INTO messages
      (id, agent_id, direction, mode, body, status, channel, metadata)
      VALUES (?, ?, 'boss_to_agent', 'async', 'React', 'sent', 'telegram', ?)`)
      .bind(id, agentId, JSON.stringify({ telegram_message_id: 123 })).run();
    const provider = vi.fn().mockImplementation(async () => {
      const row = await env.DB.prepare('SELECT metadata FROM messages WHERE id = ?')
        .bind(id).first<{ metadata: string }>();
      expect(JSON.parse(row?.metadata ?? '{}').reactions).toHaveLength(1);
      if (!succeeds) throw new Error('provider unavailable');
      return new Response(JSON.stringify({ ok: true, result: true }));
    });
    vi.stubGlobal('fetch', provider);
    const response = await SELF.fetch(`https://test.local/api/messages/${id}/react`, {
      method: 'POST', headers: authHeaders(), body: JSON.stringify({ emoji: '👍' }),
    });
    expect(response.status).toBe(200);
    expect(provider).toHaveBeenCalledWith(expect.stringContaining('/setMessageReaction'), expect.any(Object));
  });
});

describe('GET /api/messages/:id/reactions', () => {
  const agentId = getTestAgentId();

  it('returns empty array for message without reactions', async () => {
    const msgId = 'react-test-none';
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, body, status, channel) VALUES (?, ?, 'boss_to_agent', 'async', 'No reactions', 'sent', 'api')"
    ).bind(msgId, agentId).run();

    const res = await SELF.fetch(`https://test.local/api/messages/${msgId}/reactions`, {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { reactions: unknown[] };
    expect(data.reactions).toEqual([]);
  });

  it('returns reactions from metadata', async () => {
    const msgId = 'react-test-meta';
    const reactions = [{ emoji: '🚀', user: 'agent-1' }];
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, body, status, channel, metadata) VALUES (?, ?, 'boss_to_agent', 'async', 'With meta reactions', 'sent', 'api', ?)"
    ).bind(msgId, agentId, JSON.stringify({ reactions })).run();

    const res = await SELF.fetch(`https://test.local/api/messages/${msgId}/reactions`, {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { reactions: unknown[] };
    expect(data.reactions).toEqual(reactions);
  });
});

describe('resolveDiscordChannelId (thread routing)', () => {
  const agentId = getTestAgentId();

  it('returns the session thread id when threads are enabled', async () => {
    const { resolveDiscordChannelId } = await import('./agent-delivery');
    await env.DB.prepare(
      "INSERT OR IGNORE INTO sessions (id, agent_id, discord_thread_id) VALUES (?, ?, ?)"
    ).bind('rd-sess-thread', agentId, 'thread-999').run();
    const channelId = await resolveDiscordChannelId(env, { channel_id: 'parent-000', use_threads: true }, 'rd-sess-thread');
    expect(channelId).toBe('thread-999'); // NOT the parent channel — this is the bug fix
  });

  it('falls back to config channel_id when threads are disabled', async () => {
    const { resolveDiscordChannelId } = await import('./agent-delivery');
    await env.DB.prepare(
      "INSERT OR IGNORE INTO sessions (id, agent_id, discord_thread_id) VALUES (?, ?, ?)"
    ).bind('rd-sess-nothread', agentId, 'thread-888').run();
    const channelId = await resolveDiscordChannelId(env, { channel_id: 'parent-000' }, 'rd-sess-nothread');
    expect(channelId).toBe('parent-000');
  });

  it('falls back to config channel_id when the session has no thread', async () => {
    const { resolveDiscordChannelId } = await import('./agent-delivery');
    const channelId = await resolveDiscordChannelId(env, { channel_id: 'parent-000', use_threads: true }, 'no-such-session');
    expect(channelId).toBe('parent-000');
  });
});
