// Boss reply, forwarding, and session-command HTTP regression tests.
// Uses the authenticated Worker API, seeded D1 messages, and mocked provider fetch.
import { env, SELF } from 'cloudflare:test';
import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { seedDatabase, getTestAgentId, authHeaders, seedBossToken } from '../test-helpers';
const BOSS_TOKEN = 'hb_boss_aabbccddeeff00112233445566778899';
beforeAll(async () => {
  await seedDatabase();
  await seedBossToken('API Boss', 'admin', BOSS_TOKEN);
  for (const [id, body, priority] of [['boss-api-msg-1', 'Hello from agent', 'normal'], ['boss-api-msg-2', 'Deploy completed successfully', 'high']]) {
    await env.DB.prepare("INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority) VALUES (?, ?, 'agent_to_boss', 'async', 'api', ?, 'sent', ?)")
      .bind(id, getTestAgentId(), body, priority).run();
  }
});
afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); });
function bossHeaders(): Record<string, string> {
  return { Authorization: `Bearer ${BOSS_TOKEN}`, 'Content-Type': 'application/json' };
}

describe('POST /api/boss/messages/:id/reply', () => {
  it('boss replies to agent message', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/messages/boss-api-msg-1/reply', {
      method: 'POST',
      headers: bossHeaders(),
      body: JSON.stringify({ body: 'Good work!' }),
    });
    expect(res.status).toBe(201);
    const data = await res.json() as { direction: string; reply_to: string; body: string };
    expect(data.direction).toBe('boss_to_agent');
    expect(data.reply_to).toBe('boss-api-msg-1');
    expect(data.body).toBe('Good work!');
  });

});

describe('POST /api/boss/messages/:id/reply', () => {
  it('scopes the reply to the parent message\'s session (conversation affinity)', async () => {
    // Two live sessions under the same agent; the boss replies to a message
    // authored by session A. The reply must be targeted at session A only, so
    // session B never drains it (the mis-routing regression).
    for (const sid of ['affinity-sess-a', 'affinity-sess-b']) {
      await env.DB.prepare(
        "INSERT INTO sessions (id, agent_id, label, status) VALUES (?, ?, ?, 'working')"
      ).bind(sid, getTestAgentId(), sid).run();
    }
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, session_id) VALUES (?, ?, 'agent_to_boss', 'async', 'api', ?, 'sent', 'normal', ?)"
    ).bind('affinity-parent', getTestAgentId(), 'Question from session A', 'affinity-sess-a').run();

    const res = await SELF.fetch('http://localhost/api/boss/messages/affinity-parent/reply', {
      method: 'POST',
      headers: bossHeaders(),
      body: JSON.stringify({ body: 'Do the two immediate fixes' }),
    });
    expect(res.status).toBe(201);
    const reply = await res.json() as { id: string; target_session_id: string | null };
    expect(reply.target_session_id).toBe('affinity-sess-a');
    const event = await env.DB.prepare('SELECT session_id, message_id FROM session_events WHERE message_id = ?').bind(reply.id).first<{ session_id: string; message_id: string }>();
    expect(event).toEqual({ session_id: 'affinity-sess-a', message_id: reply.id });

    // Session A sees it as unread; session B does not.
    const unreadFor = async (sid: string) => {
      const r = await SELF.fetch(
        `https://test.local/api/messages?unread=true&direction=boss_to_agent&target_session=${sid}`,
        { headers: authHeaders() },
      );
      const body = await r.json() as { messages: { id: string }[] };
      return body.messages.some((m) => m.id === reply.id);
    };
    expect(await unreadFor('affinity-sess-a')).toBe(true);
    expect(await unreadFor('affinity-sess-b')).toBe(false);
  });

});

describe('POST /api/boss/messages/:id/reply', () => {
  it('rejects empty reply body', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/messages/boss-api-msg-2/reply', {
      method: 'POST',
      headers: bossHeaders(),
      body: JSON.stringify({ body: '' }),
    });
    expect(res.status).toBe(400);
  });

  it('returns 404 for unknown parent', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/messages/nonexistent/reply', {
      method: 'POST',
      headers: bossHeaders(),
      body: JSON.stringify({ body: 'Reply' }),
    });
    expect(res.status).toBe(404);
  });

});

describe('POST /api/boss/messages/:id/reply', () => {
  it('removes Discord buttons when an API client selects an option', async () => {
    const messageId = `boss-api-discord-option-${Date.now()}`;
    await env.DB.prepare(
      "INSERT OR REPLACE INTO channel_configs (id, agent_id, channel, config) VALUES (?, ?, 'discord', ?)"
    ).bind(
      `boss-api-discord-config-${Date.now()}`,
      getTestAgentId(),
      JSON.stringify({ webhook_url: 'https://discord.test/webhook' }),
    ).run();
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, metadata, expires_at) VALUES (?, ?, 'agent_to_boss', 'blocking', 'discord', ?, 'delivered', 'normal', ?, ?)"
    ).bind(
      messageId,
      getTestAgentId(),
      'Choose cleanup',
      JSON.stringify({ options: ['Approve', 'Wait'], discord_message_id: 'discord-option-1' }),
      new Date(Date.now() + 60_000).toISOString(),
    ).run();
    const fetchMock = vi.fn().mockResolvedValue(new Response('{}', { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);

    const res = await SELF.fetch(`http://localhost/api/boss/messages/${messageId}/reply`, {
      method: 'POST',
      headers: bossHeaders(),
      body: JSON.stringify({ body: 'Approve' }),
    });

    expect(res.status).toBe(201);
    await new Promise((resolve) => setTimeout(resolve, 50));
    expect(fetchMock).toHaveBeenCalledWith(
      'https://discord.test/webhook/messages/discord-option-1',
      expect.objectContaining({
        method: 'PATCH',
        body: expect.stringContaining('"components":[]'),
      }),
    );
  });
});

describe('POST /api/boss/messages/:id/forward', () => {
  it('rejects invalid target channels', async () => {
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority) VALUES (?, ?, 'agent_to_boss', 'async', 'discord', ?, 'sent', 'normal')"
    ).bind('boss-forward-source', getTestAgentId(), 'Ship this update').run();

    const res = await SELF.fetch('http://localhost/api/boss/messages/boss-forward-source/forward', {
      method: 'POST',
      headers: bossHeaders(),
      body: JSON.stringify({ channel: 'api' }),
    });
    expect(res.status).toBe(400);
    expect(await res.text()).toContain('channel must be discord or telegram');
  });

  it('rejects forwarding boss-authored messages', async () => {
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority) VALUES (?, ?, 'boss_to_agent', 'async', 'api', ?, 'sent', 'normal')"
    ).bind('boss-forward-blocked', getTestAgentId(), 'Do not forward this').run();

    const res = await SELF.fetch('http://localhost/api/boss/messages/boss-forward-blocked/forward', {
      method: 'POST',
      headers: bossHeaders(),
      body: JSON.stringify({ channel: 'telegram' }),
    });
    expect(res.status).toBe(403);
    expect(await res.text()).toBe('cannot forward boss messages');
  });
});

describe('GET /api/boss/sessions', () => {
  it('lists sessions for accessible agents', async () => {
    // Register a session first
    await env.DB.prepare(
      "INSERT OR REPLACE INTO sessions (id, agent_id, label, status, last_seen_at) VALUES (?, ?, ?, ?, datetime('now'))"
    ).bind('boss-sess-1', getTestAgentId(), 'test-session', 'working').run();

    const res = await SELF.fetch('http://localhost/api/boss/sessions', { headers: bossHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as { sessions: unknown[] };
    expect(data.sessions).toBeInstanceOf(Array);
  });
});

describe('POST /api/boss/sessions/:id/message', () => {
  it('sends a fresh command to a session agent', async () => {
    await env.DB.prepare(
      "INSERT INTO sessions (id, agent_id, label, status) VALUES (?, ?, ?, 'working')"
    ).bind('boss-sess-cmd', getTestAgentId(), 'cmd-session').run();
    const res = await SELF.fetch('http://localhost/api/boss/sessions/boss-sess-cmd/message', {
      method: 'POST',
      headers: bossHeaders(),
      body: JSON.stringify({ body: 'Run the deploy', priority: 'high' }),
    });
    expect(res.status).toBe(201);
    const data = await res.json() as { id: string; direction: string; target_session_id: string; priority: string; body: string };
    expect(data.direction).toBe('boss_to_agent');
    expect(data.target_session_id).toBe('boss-sess-cmd');
    expect(data.priority).toBe('high');
    expect(data.body).toBe('Run the deploy');
    const event = await env.DB.prepare('SELECT session_id, message_id FROM session_events WHERE message_id = ?').bind(data.id).first<{ session_id: string; message_id: string }>();
    expect(event).toEqual({ session_id: 'boss-sess-cmd', message_id: data.id });
  });

  it('rejects empty body', async () => {
    await env.DB.prepare(
      "INSERT INTO sessions (id, agent_id, label, status) VALUES (?, ?, ?, 'working')"
    ).bind('boss-sess-cmd-2', getTestAgentId(), 'cmd-session-2').run();
    const res = await SELF.fetch('http://localhost/api/boss/sessions/boss-sess-cmd-2/message', {
      method: 'POST',
      headers: bossHeaders(),
      body: JSON.stringify({ body: '  ' }),
    });
    expect(res.status).toBe(400);
  });

  it('returns 404 for unknown session', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/sessions/nope-nope/message', {
      method: 'POST',
      headers: bossHeaders(),
      body: JSON.stringify({ body: 'hi' }),
    });
    expect(res.status).toBe(404);
  });
});
