// Tests for /api/boss/* endpoints: boss-authenticated profile, preferences, messages, sessions.
// Covers boss auth flow, message listing with search, and reply.
// Depends on cloudflare:test, test-helpers, and the Hono app.

import { env, SELF } from 'cloudflare:test';
import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { seedDatabase, getTestAgentId } from '../test-helpers';
import { hashApiKey } from '../middleware/auth';

const BOSS_TOKEN = 'hb_boss_aabbccddeeff00112233445566778899';
let bossId: string;

beforeAll(async () => {
  await seedDatabase();
  // Create boss with token
  const tokenHash = await hashApiKey(BOSS_TOKEN);
  const row = await env.DB
    .prepare('INSERT INTO bosses (name, role, token_hash) VALUES (?, ?, ?) RETURNING id')
    .bind('API Boss', 'admin', tokenHash)
    .first<{ id: string }>();
  bossId = row!.id;
  // Grant access to test agent
  await env.DB
    .prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
    .bind(bossId, getTestAgentId())
    .run();
  // Seed messages from test agent
  await env.DB.prepare(
    "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority) VALUES (?, ?, 'agent_to_boss', 'async', 'api', ?, 'sent', 'normal')"
  ).bind('boss-api-msg-1', getTestAgentId(), 'Hello from agent').run();
  await env.DB.prepare(
    "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority) VALUES (?, ?, 'agent_to_boss', 'async', 'api', ?, 'sent', 'high')"
  ).bind('boss-api-msg-2', getTestAgentId(), 'Deploy completed successfully').run();
});

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

function bossHeaders(): Record<string, string> {
  return { Authorization: `Bearer ${BOSS_TOKEN}`, 'Content-Type': 'application/json' };
}

describe('Boss auth', () => {
  it('rejects invalid token', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/me', {
      headers: { Authorization: 'Bearer hb_boss_invalid', 'Content-Type': 'application/json' },
    });
    expect(res.status).toBe(401);
  });

  it('rejects agent key on boss endpoint', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/me', {
      headers: { Authorization: 'Bearer hb_test_key_0000000000000000', 'Content-Type': 'application/json' },
    });
    expect(res.status).toBe(401);
  });
});

describe('GET /api/boss/me', () => {
  it('returns boss profile', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/me', { headers: bossHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as any;
    expect(data.id).toBe(bossId);
    expect(data.name).toBe('API Boss');
    expect(data.role).toBe('admin');
    expect(data.agent_ids).toBeInstanceOf(Array);
  });
});

describe('Boss preferences', () => {
  it('GET /api/boss/me/preferences returns empty by default', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/me/preferences', { headers: bossHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as any;
    expect(data).toEqual({});
  });

  it('PUT /api/boss/me/preferences sets and merges', async () => {
    // Set initial
    const res1 = await SELF.fetch('http://localhost/api/boss/me/preferences', {
      method: 'PUT',
      headers: bossHeaders(),
      body: JSON.stringify({ preferred_channel: 'telegram' }),
    });
    expect(res1.status).toBe(200);
    const data1 = await res1.json() as any;
    expect(data1.preferred_channel).toBe('telegram');
    // Merge more
    const res2 = await SELF.fetch('http://localhost/api/boss/me/preferences', {
      method: 'PUT',
      headers: bossHeaders(),
      body: JSON.stringify({ timezone: 'Asia/Shanghai' }),
    });
    expect(res2.status).toBe(200);
    const data2 = await res2.json() as any;
    expect(data2.preferred_channel).toBe('telegram');
    expect(data2.timezone).toBe('Asia/Shanghai');
  });
});

describe('GET /api/boss/agents', () => {
  it('returns accessible agents', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/agents', { headers: bossHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as any;
    expect(data.agents).toBeInstanceOf(Array);
    // Admin sees all agents, should include test-agent
    const names = data.agents.map((a: any) => a.name);
    expect(names).toContain('test-agent');
  });
});

describe('GET /api/boss/messages', () => {
  it('lists agent messages', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/messages', { headers: bossHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as any;
    expect(data.messages).toBeInstanceOf(Array);
    expect(data.total).toBeGreaterThanOrEqual(2);
  });

  it('filters by unread', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/messages?unread=true', { headers: bossHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as any;
    for (const m of data.messages) {
      expect(['sent', 'delivered']).toContain(m.status);
    }
  });

  it('filters by priority', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/messages?priority=high', { headers: bossHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as any;
    for (const m of data.messages) {
      expect(m.priority).toBe('high');
    }
  });

  it('supports search filter', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/messages?search=Deploy', { headers: bossHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as any;
    expect(data.messages.length).toBeGreaterThanOrEqual(1);
    for (const m of data.messages) {
      expect(m.body.toLowerCase()).toContain('deploy');
    }
  });

  it('search returns empty for no match', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/messages?search=xyznonexistent', { headers: bossHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as any;
    expect(data.messages.length).toBe(0);
  });

  it('supports limit and offset', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/messages?limit=1&offset=0', { headers: bossHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as any;
    expect(data.messages.length).toBeLessThanOrEqual(1);
  });

  it('filters by agent', async () => {
    const res = await SELF.fetch(`http://localhost/api/boss/messages?agent=${getTestAgentId()}`, { headers: bossHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as any;
    expect(data.messages.length).toBeGreaterThanOrEqual(1);
  });
});

describe('GET /api/boss/messages/:id', () => {
  it('returns message with replies', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/messages/boss-api-msg-1', { headers: bossHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as any;
    expect(data.id).toBe('boss-api-msg-1');
    expect(data.replies).toBeInstanceOf(Array);
  });

  it('returns 404 for unknown message', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/messages/nonexistent', { headers: bossHeaders() });
    expect(res.status).toBe(404);
  });
});

describe('POST /api/boss/messages/:id/reply', () => {
  it('boss replies to agent message', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/messages/boss-api-msg-1/reply', {
      method: 'POST',
      headers: bossHeaders(),
      body: JSON.stringify({ body: 'Good work!' }),
    });
    expect(res.status).toBe(201);
    const data = await res.json() as any;
    expect(data.direction).toBe('boss_to_agent');
    expect(data.reply_to).toBe('boss-api-msg-1');
    expect(data.body).toBe('Good work!');
  });

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
    const data = await res.json() as any;
    expect(data.sessions).toBeInstanceOf(Array);
  });
});
