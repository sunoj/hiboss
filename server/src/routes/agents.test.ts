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
