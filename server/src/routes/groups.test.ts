// Integration tests for /api/groups endpoints.
// Covers group CRUD, membership, and broadcast.
// Depends on cloudflare:test env, auth hashing, and shared test helpers.

import { testRequest, returnsStatus } from '../test-request';
import { env } from 'cloudflare:test';
import { describe, it, expect, beforeAll } from 'vitest';
import { seedDatabase, authHeaders, getTestAgentId } from '../test-helpers';
import { hashApiKey } from '../middleware/auth';

beforeAll(async () => {
  await seedDatabase();
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

describe('GET /api/groups', () => {
  it('returns empty list initially', async () => {
    const res = await testRequest('GET', 'https://test.local/api/groups', authHeaders());
    expect(res.status).toBe(200);
    const data = (await res.json()) as { groups: unknown[] };
    expect(data.groups).toBeInstanceOf(Array);
  });

  it('scopes groups to the authenticated owner', async () => {
    const otherHeaders = await createAgentAuth('group-agent-2', 'hb_test_key_group_agent_2_000000');
    const ownCreate = await testRequest('POST', 'https://test.local/api/groups', authHeaders(),
      { name: 'owner-scope-a' });
    const otherCreate = await testRequest('POST', 'https://test.local/api/groups', otherHeaders,
      { name: 'owner-scope-b' });
    const otherGroup = await otherCreate.json() as { id: string };
    expect(ownCreate.status).toBe(201);
    expect(otherCreate.status).toBe(201);

    const ownList = await testRequest('GET', 'https://test.local/api/groups', authHeaders());
    expect(ownList.status).toBe(200);
    const ownData = await ownList.json() as { groups: { name: string }[] };
    expect(ownData.groups.some((group) => group.name === 'owner-scope-a')).toBe(true);
    expect(ownData.groups.some((group) => group.name === 'owner-scope-b')).toBe(false);

    const ownGetOther = await testRequest('GET', `https://test.local/api/groups/${otherGroup.id}`,
      authHeaders());
    expect(ownGetOther.status).toBe(404);
  });
});

describe('POST /api/groups', () => {
  it('creates a group', async () => {
    const res = await testRequest('POST', 'https://test.local/api/groups', authHeaders(),
      { name: 'test-group', description: 'A test group' });
    expect(res.status).toBe(201);
    const data = (await res.json()) as { id: string; name: string; description: string };
    expect(data.name).toBe('test-group');
    expect(data.description).toBe('A test group');
  });

  it('rejects empty name', returnsStatus(400, () =>
    testRequest('POST', 'https://test.local/api/groups', authHeaders(), { name: '' })));
});

describe('GET /api/groups/:id', () => {
  it('gets group by id with members', async () => {
    const create = await testRequest('POST', 'https://test.local/api/groups', authHeaders(),
      { name: 'detail-group' });
    const group = (await create.json()) as { id: string };

    const res = await testRequest('GET', `https://test.local/api/groups/${group.id}`, authHeaders());
    expect(res.status).toBe(200);
    const data = (await res.json()) as { name: string; members: unknown[] };
    expect(data.name).toBe('detail-group');
    expect(data.members).toBeInstanceOf(Array);
  });

  it('looks up group by name', returnsStatus(200, () =>
    testRequest('GET', 'https://test.local/api/groups/detail-group', authHeaders())));

  it('returns 404 for non-existent group', returnsStatus(404, () =>
    testRequest('GET', 'https://test.local/api/groups/nonexistent', authHeaders())));
});

describe('POST /api/groups/:id/members', () => {
  it('adds a member to a group', async () => {
    const create = await testRequest('POST', 'https://test.local/api/groups', authHeaders(),
      { name: 'member-group' });
    const group = (await create.json()) as { id: string };

    const res = await testRequest('POST', `https://test.local/api/groups/${group.id}/members`, authHeaders(),
      { agent_id: getTestAgentId() });
    expect(res.status).toBe(201);
  });

  it('is idempotent for same member', async () => {
    const list = await testRequest('GET', 'https://test.local/api/groups/member-group', authHeaders());
    const group = (await list.json()) as { id: string };

    const res = await testRequest('POST', `https://test.local/api/groups/${group.id}/members`, authHeaders(),
      { agent_id: getTestAgentId() });
    expect(res.status).toBe(201);
  });
});

describe('DELETE /api/groups/:id/members/:agentId', () => {
  it('removes a member', async () => {
    const list = await testRequest('GET', 'https://test.local/api/groups/member-group', authHeaders());
    const group = (await list.json()) as { id: string };

    const res = await testRequest('DELETE',
      `https://test.local/api/groups/${group.id}/members/${getTestAgentId()}`, authHeaders());
    expect(res.status).toBe(200);
  });
});

describe('POST /api/groups/:id/broadcast', () => {
  it('broadcasts to all group members', async () => {
    const list = await testRequest('GET', 'https://test.local/api/groups/member-group', authHeaders());
    const group = (await list.json()) as { id: string };

    // Re-add member
    await testRequest('POST', `https://test.local/api/groups/${group.id}/members`, authHeaders(),
      { agent_id: getTestAgentId() });

    const res = await testRequest('POST', `https://test.local/api/groups/${group.id}/broadcast`,
      authHeaders(), { body: 'Hello everyone', priority: 'normal' });
    expect(res.status).toBe(201);
    const data = (await res.json()) as { count: number; messages: { agent_id: string; message_id: string }[] };
    expect(data.count).toBe(1);
    expect(data.messages[0].agent_id).toBe(getTestAgentId());
  });

  it('rejects empty body', async () => {
    const list = await testRequest('GET', 'https://test.local/api/groups/member-group', authHeaders());
    const group = (await list.json()) as { id: string };

    const res = await testRequest('POST', `https://test.local/api/groups/${group.id}/broadcast`,
      authHeaders(), { body: '' });
    expect(res.status).toBe(400);
  });
});

describe('DELETE /api/groups/:id', () => {
  it('deletes a group', async () => {
    const create = await testRequest('POST', 'https://test.local/api/groups', authHeaders(),
      { name: 'delete-me' });
    const group = (await create.json()) as { id: string };

    const res = await testRequest('DELETE', `https://test.local/api/groups/${group.id}`, authHeaders());
    expect(res.status).toBe(200);
  });

  it('returns 404 for non-existent group', returnsStatus(404, () =>
    testRequest('DELETE', 'https://test.local/api/groups/nonexistent', authHeaders())));
});
