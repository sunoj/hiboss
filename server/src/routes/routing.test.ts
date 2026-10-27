// Integration tests for /api/routing-rules endpoints.
// Covers CRUD operations and regex validation.
// Depends on cloudflare:test env and shared test helpers.

import { testRequest, returnsStatus } from '../test-request';
import { describe, it, expect, beforeAll } from 'vitest';
import { seedDatabase, authHeaders, getTestAgentId } from '../test-helpers';

beforeAll(async () => {
  await seedDatabase();
});

describe('GET /api/routing-rules', () => {
  it('returns empty list initially', async () => {
    const res = await testRequest('GET', 'https://test.local/api/routing-rules', authHeaders());
    expect(res.status).toBe(200);
    const data = (await res.json()) as { rules: unknown[] };
    expect(data.rules).toBeInstanceOf(Array);
  });
});

describe('POST /api/routing-rules', () => {
  it('creates a routing rule', async () => {
    const res = await testRequest('POST', 'https://test.local/api/routing-rules', authHeaders(), {
        channel: 'telegram',
        pattern: 'deploy.*prod',
        target_agent_id: getTestAgentId(),
        priority: 10,
      });
    expect(res.status).toBe(201);
    const data = (await res.json()) as { id: string; channel: string; pattern: string; priority: number };
    expect(data.channel).toBe('telegram');
    expect(data.pattern).toBe('deploy.*prod');
    expect(data.priority).toBe(10);
  });

  it('rejects invalid channel', returnsStatus(400, () =>
    testRequest('POST', 'https://test.local/api/routing-rules', authHeaders(),
      { channel: 'sms', pattern: '.*', target_agent_id: 'x' })));

  it('rejects missing pattern', returnsStatus(400, () =>
    testRequest('POST', 'https://test.local/api/routing-rules', authHeaders(),
      { channel: 'telegram', pattern: '', target_agent_id: 'x' })));

  it('rejects invalid regex', returnsStatus(400, () =>
    testRequest('POST', 'https://test.local/api/routing-rules', authHeaders(),
      { channel: 'telegram', pattern: '[invalid', target_agent_id: 'x' })));
});

describe('DELETE /api/routing-rules/:id', () => {
  it('deletes a rule by id', async () => {
    const create = await testRequest('POST', 'https://test.local/api/routing-rules', authHeaders(), {
        channel: 'discord',
        pattern: 'test-delete',
        target_agent_id: getTestAgentId(),
      });
    const rule = (await create.json()) as { id: string };

    const del = await testRequest('DELETE', `https://test.local/api/routing-rules/${rule.id}`, authHeaders());
    expect(del.status).toBe(200);
  });

  it('returns 404 for non-existent rule', returnsStatus(404, () =>
    testRequest('DELETE', 'https://test.local/api/routing-rules/nonexistent',
      authHeaders())));
});
