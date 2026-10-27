// Integration tests for /api/groups endpoints.
// Covers group CRUD, membership, and broadcast.
// Depends on cloudflare:test env, auth hashing, and shared test helpers.

import { testRequest, returnsStatus, testJson } from '../test-request';
import { env } from 'cloudflare:test';
import { describe, it, expect, beforeAll } from 'vitest';
import { seedDatabase, authHeaders, getTestAgentId, createAgentAuth } from '../test-helpers';

beforeAll(async () => {
  await seedDatabase();
});

describe('GET /api/groups', () => {
  it('returns empty list initially', async () => {
    const data = (await testJson(200,
      testRequest('GET', 'https://test.local/api/groups', authHeaders()))) as { groups: unknown[] };
    expect(data.groups).toEqual([]);
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

    const ownData = await testJson(200,
      testRequest('GET', 'https://test.local/api/groups', authHeaders())) as { groups: { name: string }[] };
    expect(ownData.groups.some((group) => group.name === 'owner-scope-a')).toBe(true);
    expect(ownData.groups.some((group) => group.name === 'owner-scope-b')).toBe(false);

    const ownGetOther = await testRequest('GET', `https://test.local/api/groups/${otherGroup.id}`,
      authHeaders());
    expect(ownGetOther.status).toBe(404);
  });
});

describe('POST /api/groups', () => {
  it('creates a group', async () => {
    const data = (await testJson(201, testRequest('POST', 'https://test.local/api/groups', authHeaders(),
      { name: 'test-group', description: 'A test group' })
    )) as { id: string; name: string; description: string };
    expect(data.name).toBe('test-group');
    expect(data.description).toBe('A test group');
  });

  it.each([
    ['rejects empty name', ''],
    ['rejects whitespace name', ' \t\n'],
    ['rejects missing name', undefined],
    ['rejects null name', null],
    ['rejects numeric name', 0],
    ['rejects boolean name', false],
    ['rejects object name', {}],
    ['rejects array name', []],
  ])('%s', async (_title, name) => {
    const before = await env.DB.prepare('SELECT COUNT(*) AS total FROM agent_groups').first();
    const response = await testRequest('POST', 'https://test.local/api/groups', authHeaders(), { name });
    expect(response.status).toBe(400);
    expect(await response.text()).toBe('name is required');
    expect(await env.DB.prepare('SELECT COUNT(*) AS total FROM agent_groups').first()).toEqual(before);
  });
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
