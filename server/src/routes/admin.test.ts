// Admin integration tests covering channel and API key management scenarios.
// Exports channel configuration checks and API key endpoints used by the admin router.
// Depends on the cloudflare:test runtime and shared test helpers for auth and seeding.

import { testRequest, returnsStatus, testJson } from '../test-request';
import { env } from 'cloudflare:test';
import { describe, expect, it, beforeAll } from 'vitest';
import { seedDatabase, authHeaders, getTestAgentId } from '../test-helpers';

beforeAll(async () => {
  await seedDatabase();
  await env.DB.prepare('UPDATE api_keys SET is_admin = ? WHERE id = ?')
    .bind(1, getTestAgentId())
    .run();
});

const API_BASE = 'https://test.local/api';

async function clearChannelConfigs(): Promise<void> {
}

describe('POST /api/keys', () => {
  it('creates a new API key when provided a valid name', async () => {
    const payload = { name: 'new-agent' };

    const data = (await testJson(201, testRequest('POST', `${API_BASE}/keys`, authHeaders(), payload)
    )) as { id: string; name: string; key: string };

    expect(typeof data.id).toBe('string');
    expect(data.name).toBe(payload.name);
    expect(typeof data.key).toBe('string');
  });

  it('rejects empty names', returnsStatus(400, () =>
    testRequest('POST', `${API_BASE}/keys`, authHeaders(), { name: '   ' })));
});

describe('GET /api/keys', () => {
  it('lists API keys including the test agent key', async () => {
    const data = (await testJson(200, testRequest('GET', `${API_BASE}/keys`, authHeaders()))) as {
      keys: Array<{ id: string; name: string; created_at: string; last_used_at: string | null }>;
    };

    expect(Array.isArray(data.keys)).toBe(true);
    const testAgent = data.keys.find((entry) => entry.id === getTestAgentId());
    expect(testAgent).toBeDefined();
    expect(testAgent?.name).toBe('test-agent');
  });
});
