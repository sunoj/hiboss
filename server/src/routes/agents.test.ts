// Integration tests for agent routes and callback management.
// Covers /api/agents/me profile, listing, and callback endpoints.
// Depends on cloudflare:test infrastructure and shared test helpers.

import { env, SELF } from 'cloudflare:test';
import { describe, expect, it, beforeAll } from 'vitest';
import { seedDatabase, authHeaders, getTestAgentId } from '../test-helpers';

beforeAll(async () => {
  await seedDatabase();
});

describe('GET /api/agents/me', () => {
  it('returns the test agent profile', async () => {
    const res = await SELF.fetch('https://test.local/api/agents/me', {
      headers: authHeaders(),
    });

    expect(res.status).toBe(200);
    const data = (await res.json()) as {
      id: string;
      name: string;
      callback_url: string | null;
      last_used_at: string | null;
      created_at: string;
    };

    expect(data.id).toBe(getTestAgentId());
    expect(data.name).toBe('test-agent');
    expect(typeof data.created_at).toBe('string');
    expect('last_used_at' in data).toBe(true);
    expect('callback_url' in data).toBe(true);
  });
});

describe('GET /api/agents', () => {
  it('lists agents with status info', async () => {
    const agentId = getTestAgentId();
    const now = new Date();
    const timestamp = now.toISOString().slice(0, 19).replace('T', ' ');
    await env.DB
      .prepare('UPDATE api_keys SET last_used_at = ? WHERE id = ?')
      .bind(timestamp, agentId)
      .run();

    const res = await SELF.fetch('https://test.local/api/agents', {
      headers: authHeaders(),
    });

    expect(res.status).toBe(200);
    const data = (await res.json()) as {
      agents: Array<{ id: string; status: 'online' | 'idle' | 'offline' } & Record<string, unknown>>;
    };

    expect(Array.isArray(data.agents)).toBe(true);
    const agent = data.agents.find((item) => item.id === agentId);
    expect(agent).toBeDefined();
    expect(['online', 'idle', 'offline']).toContain(agent?.status);
  });
});

describe('PUT /api/agents/me/callback', () => {
  it('sets the callback URL and returns it', async () => {
    const callbackUrl = 'https://example.com/agent-callback';
    const res = await SELF.fetch('https://test.local/api/agents/me/callback', {
      method: 'PUT',
      headers: authHeaders(),
      body: JSON.stringify({ url: callbackUrl }),
    });

    expect(res.status).toBe(200);
    const data = (await res.json()) as { callback_url: string };
    expect(data.callback_url).toBe(callbackUrl);

    const profile = await SELF.fetch('https://test.local/api/agents/me', {
      headers: authHeaders(),
    });
    const profileData = (await profile.json()) as { callback_url: string | null };
    expect(profileData.callback_url).toBe(callbackUrl);
  });

  it('rejects empty URLs', async () => {
    const res = await SELF.fetch('https://test.local/api/agents/me/callback', {
      method: 'PUT',
      headers: authHeaders(),
      body: JSON.stringify({ url: '   ' }),
    });

    expect(res.status).toBe(400);
  });
});

describe('DELETE /api/agents/me/callback', () => {
  it('removes the callback URL and returns 204', async () => {
    await SELF.fetch('https://test.local/api/agents/me/callback', {
      method: 'PUT',
      headers: authHeaders(),
      body: JSON.stringify({ url: 'https://temporary.example/callback' }),
    });

    const res = await SELF.fetch('https://test.local/api/agents/me/callback', {
      method: 'DELETE',
      headers: authHeaders(),
    });

    expect(res.status).toBe(204);
    const profile = await SELF.fetch('https://test.local/api/agents/me', {
      headers: authHeaders(),
    });
    const profileData = (await profile.json()) as { callback_url: string | null };
    expect(profileData.callback_url).toBeNull();
  });
});

describe('PUT /api/agents/me/config', () => {
  it('updates default_priority', async () => {
    const res = await SELF.fetch('https://test.local/api/agents/me/config', {
      method: 'PUT',
      headers: authHeaders(),
      body: JSON.stringify({ default_priority: 'high' }),
    });
    expect(res.status).toBe(200);
    const data = (await res.json()) as { default_priority: string };
    expect(data.default_priority).toBe('high');
  });

  it('updates rate_limit', async () => {
    const res = await SELF.fetch('https://test.local/api/agents/me/config', {
      method: 'PUT',
      headers: authHeaders(),
      body: JSON.stringify({ rate_limit: 5 }),
    });
    expect(res.status).toBe(200);
    const data = (await res.json()) as { rate_limit: number };
    expect(data.rate_limit).toBe(5);
  });

  it('sets rate_limit to null to disable', async () => {
    const res = await SELF.fetch('https://test.local/api/agents/me/config', {
      method: 'PUT',
      headers: authHeaders(),
      body: JSON.stringify({ rate_limit: null }),
    });
    expect(res.status).toBe(200);
    const data = (await res.json()) as { rate_limit: number | null };
    expect(data.rate_limit).toBeNull();
  });

  it('rejects invalid default_priority', async () => {
    const res = await SELF.fetch('https://test.local/api/agents/me/config', {
      method: 'PUT',
      headers: authHeaders(),
      body: JSON.stringify({ default_priority: 'invalid' }),
    });
    expect(res.status).toBe(400);
  });

  it('rejects negative rate_limit', async () => {
    const res = await SELF.fetch('https://test.local/api/agents/me/config', {
      method: 'PUT',
      headers: authHeaders(),
      body: JSON.stringify({ rate_limit: -1 }),
    });
    expect(res.status).toBe(400);
  });

  it('rejects empty payload', async () => {
    const res = await SELF.fetch('https://test.local/api/agents/me/config', {
      method: 'PUT',
      headers: authHeaders(),
      body: JSON.stringify({}),
    });
    expect(res.status).toBe(400);
  });

  it('updates both fields at once', async () => {
    const res = await SELF.fetch('https://test.local/api/agents/me/config', {
      method: 'PUT',
      headers: authHeaders(),
      body: JSON.stringify({ default_priority: 'low', rate_limit: 10 }),
    });
    expect(res.status).toBe(200);
    const data = (await res.json()) as { default_priority: string; rate_limit: number };
    expect(data.default_priority).toBe('low');
    expect(data.rate_limit).toBe(10);
  });
});

describe('Rate limiting', () => {
  it('returns 429 when rate limit exceeded', async () => {
    // Set rate limit to 2 msg/min
    await SELF.fetch('https://test.local/api/agents/me/config', {
      method: 'PUT',
      headers: authHeaders(),
      body: JSON.stringify({ rate_limit: 2 }),
    });

    // Clear recent messages for clean test
    await env.DB.prepare(
      "DELETE FROM messages WHERE agent_id = ? AND direction = 'agent_to_boss' AND created_at > datetime('now', '-1 minute')"
    ).bind(getTestAgentId()).run();

    // Send 2 messages (should succeed)
    for (let i = 0; i < 2; i++) {
      const res = await SELF.fetch('https://test.local/api/messages', {
        method: 'POST',
        headers: authHeaders(),
        body: JSON.stringify({ body: `Rate test ${i}` }),
      });
      expect(res.status).toBe(201);
    }

    // Third message should be rate limited
    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Rate test exceeded' }),
    });
    expect(res.status).toBe(429);

    // Reset rate limit
    await SELF.fetch('https://test.local/api/agents/me/config', {
      method: 'PUT',
      headers: authHeaders(),
      body: JSON.stringify({ rate_limit: null }),
    });
  });
});
