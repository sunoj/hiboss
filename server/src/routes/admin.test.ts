// Admin integration tests covering channel and API key management scenarios.
// Exports channel configuration checks and API key endpoints used by the admin router.
// Depends on the cloudflare:test runtime and shared test helpers for auth and seeding.

import { env, SELF } from 'cloudflare:test';
import { describe, expect, it, beforeAll } from 'vitest';
import { seedDatabase, authHeaders, getTestAgentId } from '../test-helpers';

beforeAll(async () => {
  await seedDatabase();
  await env.DB.prepare('UPDATE api_keys SET role = ? WHERE id = ?')
    .bind('admin', getTestAgentId())
    .run();
});

const API_BASE = 'https://test.local/api';

async function clearChannelConfigs(): Promise<void> {
  await env.DB.prepare('DELETE FROM channel_configs WHERE agent_id = ?').bind(getTestAgentId()).run();
}

describe('GET /api/channels', () => {
  it('returns an empty channel list when nothing is configured', async () => {
    await clearChannelConfigs();

    const res = await SELF.fetch(`${API_BASE}/channels`, {
      headers: authHeaders(),
    });

    expect(res.status).toBe(200);
    const data = (await res.json()) as { channels: Array<unknown> };

    expect(Array.isArray(data.channels)).toBe(true);
    expect(data.channels).toEqual([]);
  });

  it('rejects non-admin agents', async () => {
    await env.DB.prepare('UPDATE api_keys SET role = ? WHERE id = ?')
      .bind('viewer', getTestAgentId())
      .run();

    const res = await SELF.fetch(`${API_BASE}/channels`, {
      headers: authHeaders(),
    });

    expect(res.status).toBe(403);
    expect(await res.text()).toBe('admin access required');

    await env.DB.prepare('UPDATE api_keys SET role = ? WHERE id = ?')
      .bind('admin', getTestAgentId())
      .run();
  });
});

describe('PUT /api/channels/:channel', () => {
  it('creates a telegram configuration and persists it', async () => {
    await clearChannelConfigs();
    const payload = { bot_token: 'token-tele', chat_id: '123456' };

    const res = await SELF.fetch(`${API_BASE}/channels/telegram`, {
      method: 'PUT',
      headers: authHeaders(),
      body: JSON.stringify(payload),
    });

    expect(res.status).toBe(200);
    const data = (await res.json()) as {
      id: string;
      channel: string;
      config: Record<string, unknown>;
      enabled: boolean;
      created_at: string;
    };

    expect(typeof data.id).toBe('string');
    expect(data.channel).toBe('telegram');
    expect(data.enabled).toBe(true);
    expect(data.config).toEqual(payload);
    expect(typeof data.created_at).toBe('string');

    const stored = await env.DB
      .prepare('SELECT config, enabled FROM channel_configs WHERE agent_id = ? AND channel = ?')
      .bind(getTestAgentId(), 'telegram')
      .first<{ config: string; enabled: number }>();

    expect(stored).toBeDefined();
    expect(stored?.enabled).toBe(1);
    expect(JSON.parse(stored?.config ?? '{}')).toEqual(payload);
  });

  it('creates a discord configuration when provided valid payload', async () => {
    await clearChannelConfigs();
    const payload = { webhook_url: 'https://example.com/webhook' };

    const res = await SELF.fetch(`${API_BASE}/channels/discord`, {
      method: 'PUT',
      headers: authHeaders(),
      body: JSON.stringify(payload),
    });

    expect(res.status).toBe(200);
    const data = (await res.json()) as {
      id: string;
      channel: string;
      config: Record<string, unknown>;
      enabled: boolean;
      created_at: string;
    };

    expect(data.channel).toBe('discord');
    expect(data.config).toEqual(payload);
    expect(data.enabled).toBe(true);

    const stored = await env.DB
      .prepare('SELECT config FROM channel_configs WHERE agent_id = ? AND channel = ?')
      .bind(getTestAgentId(), 'discord')
      .first<{ config: string }>();

    expect(stored).toBeDefined();
    expect(JSON.parse(stored?.config ?? '{}')).toEqual(payload);
  });

  it('rejects an unsupported channel identifier', async () => {
    await clearChannelConfigs();

    const res = await SELF.fetch(`${API_BASE}/channels/invalid`, {
      method: 'PUT',
      headers: authHeaders(),
      body: JSON.stringify({}),
    });

    expect(res.status).toBe(400);
  });

  it('rejects non-object payloads', async () => {
    await clearChannelConfigs();

    const res = await SELF.fetch(`${API_BASE}/channels/telegram`, {
      method: 'PUT',
      headers: authHeaders(),
      body: JSON.stringify('not-an-object'),
    });

    expect(res.status).toBe(400);
  });
});

describe('POST /api/keys', () => {
  it('creates a new API key when provided a valid name', async () => {
    const payload = { name: 'new-agent' };

    const res = await SELF.fetch(`${API_BASE}/keys`, {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify(payload),
    });

    expect(res.status).toBe(201);
    const data = (await res.json()) as { id: string; name: string; key: string };

    expect(typeof data.id).toBe('string');
    expect(data.name).toBe(payload.name);
    expect(typeof data.key).toBe('string');
  });

  it('rejects empty names', async () => {
    const res = await SELF.fetch(`${API_BASE}/keys`, {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ name: '   ' }),
    });

    expect(res.status).toBe(400);
  });
});

describe('GET /api/keys', () => {
  it('lists API keys including the test agent key', async () => {
    const res = await SELF.fetch(`${API_BASE}/keys`, {
      headers: authHeaders(),
    });

    expect(res.status).toBe(200);
    const data = (await res.json()) as {
      keys: Array<{ id: string; name: string; created_at: string; last_used_at: string | null }>;
    };

    expect(Array.isArray(data.keys)).toBe(true);
    const testAgent = data.keys.find((entry) => entry.id === getTestAgentId());
    expect(testAgent).toBeDefined();
    expect(testAgent?.name).toBe('test-agent');
  });
});
