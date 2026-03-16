// Integration tests for /api/groups endpoints.
// Covers group CRUD, membership, and broadcast.
// Depends on cloudflare:test env and shared test helpers.

import { SELF } from 'cloudflare:test';
import { describe, it, expect, beforeAll } from 'vitest';
import { seedDatabase, authHeaders, getTestAgentId } from '../test-helpers';

beforeAll(async () => {
  await seedDatabase();
});

describe('GET /api/groups', () => {
  it('returns empty list initially', async () => {
    const res = await SELF.fetch('https://test.local/api/groups', {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = (await res.json()) as { groups: unknown[] };
    expect(data.groups).toBeInstanceOf(Array);
  });
});

describe('POST /api/groups', () => {
  it('creates a group', async () => {
    const res = await SELF.fetch('https://test.local/api/groups', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ name: 'test-group', description: 'A test group' }),
    });
    expect(res.status).toBe(201);
    const data = (await res.json()) as { id: string; name: string; description: string };
    expect(data.name).toBe('test-group');
    expect(data.description).toBe('A test group');
  });

  it('rejects empty name', async () => {
    const res = await SELF.fetch('https://test.local/api/groups', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ name: '' }),
    });
    expect(res.status).toBe(400);
  });
});

describe('GET /api/groups/:id', () => {
  it('gets group by id with members', async () => {
    const create = await SELF.fetch('https://test.local/api/groups', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ name: 'detail-group' }),
    });
    const group = (await create.json()) as { id: string };

    const res = await SELF.fetch(`https://test.local/api/groups/${group.id}`, {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = (await res.json()) as { name: string; members: unknown[] };
    expect(data.name).toBe('detail-group');
    expect(data.members).toBeInstanceOf(Array);
  });

  it('looks up group by name', async () => {
    const res = await SELF.fetch('https://test.local/api/groups/detail-group', {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
  });

  it('returns 404 for non-existent group', async () => {
    const res = await SELF.fetch('https://test.local/api/groups/nonexistent', {
      headers: authHeaders(),
    });
    expect(res.status).toBe(404);
  });
});

describe('POST /api/groups/:id/members', () => {
  it('adds a member to a group', async () => {
    const create = await SELF.fetch('https://test.local/api/groups', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ name: 'member-group' }),
    });
    const group = (await create.json()) as { id: string };

    const res = await SELF.fetch(`https://test.local/api/groups/${group.id}/members`, {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ agent_id: getTestAgentId() }),
    });
    expect(res.status).toBe(201);
  });

  it('is idempotent for same member', async () => {
    const list = await SELF.fetch('https://test.local/api/groups/member-group', {
      headers: authHeaders(),
    });
    const group = (await list.json()) as { id: string };

    const res = await SELF.fetch(`https://test.local/api/groups/${group.id}/members`, {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ agent_id: getTestAgentId() }),
    });
    expect(res.status).toBe(201);
  });
});

describe('DELETE /api/groups/:id/members/:agentId', () => {
  it('removes a member', async () => {
    const list = await SELF.fetch('https://test.local/api/groups/member-group', {
      headers: authHeaders(),
    });
    const group = (await list.json()) as { id: string };

    const res = await SELF.fetch(`https://test.local/api/groups/${group.id}/members/${getTestAgentId()}`, {
      method: 'DELETE',
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
  });
});

describe('POST /api/groups/:id/broadcast', () => {
  it('broadcasts to all group members', async () => {
    const list = await SELF.fetch('https://test.local/api/groups/member-group', {
      headers: authHeaders(),
    });
    const group = (await list.json()) as { id: string };

    // Re-add member
    await SELF.fetch(`https://test.local/api/groups/${group.id}/members`, {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ agent_id: getTestAgentId() }),
    });

    const res = await SELF.fetch(`https://test.local/api/groups/${group.id}/broadcast`, {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'Hello everyone', priority: 'normal' }),
    });
    expect(res.status).toBe(201);
    const data = (await res.json()) as { count: number; messages: { agent_id: string; message_id: string }[] };
    expect(data.count).toBe(1);
    expect(data.messages[0].agent_id).toBe(getTestAgentId());
  });

  it('rejects empty body', async () => {
    const list = await SELF.fetch('https://test.local/api/groups/member-group', {
      headers: authHeaders(),
    });
    const group = (await list.json()) as { id: string };

    const res = await SELF.fetch(`https://test.local/api/groups/${group.id}/broadcast`, {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: '' }),
    });
    expect(res.status).toBe(400);
  });
});

describe('DELETE /api/groups/:id', () => {
  it('deletes a group', async () => {
    const create = await SELF.fetch('https://test.local/api/groups', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ name: 'delete-me' }),
    });
    const group = (await create.json()) as { id: string };

    const res = await SELF.fetch(`https://test.local/api/groups/${group.id}`, {
      method: 'DELETE',
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
  });

  it('returns 404 for non-existent group', async () => {
    const res = await SELF.fetch('https://test.local/api/groups/nonexistent', {
      method: 'DELETE',
      headers: authHeaders(),
    });
    expect(res.status).toBe(404);
  });
});
